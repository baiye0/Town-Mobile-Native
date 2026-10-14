import SwiftUI
@preconcurrency import Speech
@preconcurrency import AVFoundation

@MainActor @Observable final class SpeechInput {
    var active = false
    private var generation = UUID()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timer: Task<Void,Never>?
    private var tapped = false
    private var hasTranscript = false
    private(set) var finishing = false
    private(set) var startedAt: Date?
    private(set) var levels = Array(repeating: Float(0), count: 36)
    private var lastMeterUpdate = Date.distantPast
    private func meter(_ value: Float, generation id: UUID) {
        guard generation == id, active, !finishing, Date().timeIntervalSince(lastMeterUpdate) >= 0.08 else { return }
        lastMeterUpdate = Date()
        levels.removeFirst(); levels.append(value)
    }
    func finish() {
        guard active, startedAt != nil, !finishing else { return }
        finishing = true
        if engine.isRunning { engine.stop() }
        if tapped { engine.inputNode.removeTap(onBus:0); tapped = false }
        request?.endAudio(); recognition?.finish()
        timer?.cancel()
        timer = Task { [weak self] in do { try await Task.sleep(for:.seconds(3));self?.stop() } catch {} }
    }
    func stop() {
        generation = UUID(); timer?.cancel(); timer = nil
        if engine.isRunning { engine.stop() }
        if tapped { engine.inputNode.removeTap(onBus:0); tapped = false }
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil
        if active { try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
        active = false; startedAt = nil; finishing = false
    }
    func start(update:@escaping @MainActor (String)->Void, failure:@escaping @MainActor (String)->Void) async {
        guard !active else { return }
        hasTranscript = false; finishing = false; startedAt = nil
        levels = Array(repeating: 0, count: 36); lastMeterUpdate = .distantPast
        active = true; let id = UUID(); generation = id
        let auth = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning:$0) } }
        guard generation == id else { return }
        guard auth == .authorized else { stop(); failure("请在系统设置中允许 Being 使用语音识别。"); return }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard generation == id else { return }
        guard microphone else { stop(); failure("请在系统设置中允许 Being 使用麦克风。"); return }
        guard let recognizer = SFSpeechRecognizer(locale:Locale.current),recognizer.isAvailable else { stop(); failure("系统语音识别暂不可用。"); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record,mode:.measurement,options:.duckOthers)
            try session.setActive(true,options:.notifyOthersOnDeactivation)
            let input = engine.inputNode; let format = input.outputFormat(forBus:0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw NSError(domain:"SpeechInput",code:1,userInfo:[NSLocalizedDescriptionKey:"麦克风暂不可用。"]) }
            let request = SFSpeechAudioBufferRecognitionRequest(); self.request = request
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            recognition = recognizer.recognitionTask(with:request) { [weak self] result,error in
                let text = result?.bestTranscription.formattedString; let final = result?.isFinal == true
                Task { @MainActor in
                    guard let self,self.generation == id else { return }
                    if let text, !text.isEmpty { self.hasTranscript = true; update(text) }
                    if final || error != nil {
                        let reportError = !self.hasTranscript && !self.finishing
                        self.stop()
                        if let error, reportError { failure(error.localizedDescription) }
                    }
                }
            }
            input.installTap(onBus:0,bufferSize:1024,format:format) { [weak self] buffer,_ in
                request.append(buffer)
                guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                var sum: Float = 0
                for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                let rms = sqrt(sum / Float(buffer.frameLength))
                let level = max(0, min(1, (20 * log10(max(rms, 0.00001)) + 55) / 45))
                Task { @MainActor in self?.meter(level, generation: id) }
            }; tapped = true
            engine.prepare(); try engine.start(); startedAt = Date()
            timer = Task { [weak self] in do { try await Task.sleep(for:.seconds(60));self?.finish() } catch {} }
        } catch { stop(); failure(error.localizedDescription) }
    }
}

import SwiftUI
import AVFoundation

struct AttachmentAudioView: View {
    let file: PendingAttachment
    let foreground: Color
    let loadURL: () async throws -> URL
    let loadTranscript: () async throws -> String
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVAudioPlayer?
    @State private var url: URL?
    @State private var playing = false
    @State private var loading = false
    @State private var error: String?
    @State private var position = 0.0
    @State private var duration = 0.0
    @State private var volume = 1.0
    @State private var speed: Float = 1
    @State private var settings = false
    @State private var peaks = Array(repeating: 0.12, count: 28)
    @State private var transcript = ""
    @State private var transcriptError = false
    @State private var retry = 0
    @State private var transcriptRetry = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.name).font(.caption).lineLimit(1)
            HStack(spacing: 6) {
                Button {
                    guard let player else { retry += 1; return }
                    if playing { player.pause(); playing = false }
                    else {
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                            try AVAudioSession.sharedInstance().setActive(true)
                            if player.currentTime >= duration { player.currentTime = 0 }
                            playing = player.play()
                            error = playing ? nil : "音频暂时无法播放"
                        } catch { self.error = "音频暂时无法播放" }
                    }
                } label: {
                    if loading { ProgressView().tint(.white) }
                    else { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 18) }
                }.frame(width: 44, height: 44).disabled(loading).accessibilityLabel(playing ? "暂停" : "播放")
                GeometryReader { geometry in
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(peaks.indices, id: \.self) { index in
                            Capsule().fill(Double(index) / Double(peaks.count) <= position / max(duration, 1) ? Color.white : Color.gray)
                                .frame(height: max(3, 28 * peaks[index]))
                        }
                    }.frame(height: 44).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard duration > 0 else { return }
                            position = min(1, max(0, value.location.x / max(geometry.size.width, 1))) * duration
                            player?.currentTime = position
                        })
                }.frame(minWidth: 40, maxWidth: .infinity).frame(height: 44)
                    .accessibilityElement().accessibilityLabel("播放进度").accessibilityValue(time(position) + " / " + time(duration))
                    .accessibilityAdjustableAction { direction in
                        position = min(duration, max(0, position + (direction == .increment ? 5 : -5)))
                        player?.currentTime = position
                    }
                Text(time(position) + " / " + (duration > 0 ? time(duration) : "—"))
                    .font(.system(size: 10, design: .monospaced)).fixedSize()
                Menu {
                    BeingIconButton("播放设置", systemImage: "slider.horizontal.3") { settings = true }
                    if let url { ShareLink(item: url) { Label("保存或分享音频", systemImage: "square.and.arrow.up") } }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44) }.accessibilityLabel("音频操作")
            }.buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal, 6)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14))
            if let error { Text(error).font(.caption); Button("重试播放") { retry += 1 }.font(.caption) }
            if !transcript.isEmpty { Text(transcript).font(.subheadline).textSelection(.enabled) }
            if transcriptError { Button("语音文字加载失败，重试") { transcriptRetry += 1 }.font(.caption) }
        }.foregroundStyle(foreground)
            .task(id: retry) { await prepare() }
            .task(id: "\(file.resultID ?? "")|\(transcriptRetry)") {
                guard file.resultID != nil else { return }
                transcriptError = false
                do { transcript = try await loadTranscript() } catch { if !Task.isCancelled { transcriptError = true } }
            }
            .task(id: playing) {
                while playing && !Task.isCancelled {
                    position = player?.currentTime ?? 0
                    if player?.isPlaying != true { playing = false; position = duration; break }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            .onDisappear { player?.stop(); player = nil; playing = false }
            .onChange(of: scenePhase) { phase in if phase != .active { player?.pause(); playing = false } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in player?.pause(); playing = false }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    Form {
                        Section("音量") { Slider(value: $volume, in: 0...1).accessibilityLabel("音量").onChange(of: volume) { value in player?.volume = Float(value) } }
                        Picker("播放速度", selection: $speed) { ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { value in Text("\(value.formatted())×").tag(value) } }
                            .onChange(of: speed) { value in player?.rate = value }
                    }.navigationTitle("播放设置").toolbar { Button("完成") { settings = false } }
                }.presentationDetents([.medium])
            }
    }

    private func prepare() async {
        player?.stop(); player = nil; playing = false; loading = true; error = nil
        defer { loading = false }
        do {
            let source: URL
            if let url { source = url } else { source = try await loadURL() }
            try Task.checkCancellation()
            url = source
            let audio = try AVAudioPlayer(contentsOf: source)
            audio.enableRate = true; audio.rate = speed; audio.volume = Float(volume)
            audio.prepareToPlay(); duration = audio.duration; position = 0; player = audio
            let waveform = await Task.detached(priority: .utility) { Self.waveform(source) }.value
            if !Task.isCancelled { peaks = waveform }
        } catch { if !Task.isCancelled { self.error = "音频暂时无法播放" } }
    }
    private func time(_ value: Double) -> String {
        let seconds = value.isFinite ? max(0, Int(value)) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    nonisolated private static func waveform(_ url: URL) -> [Double] {
        let fallback = Array(repeating: 0.12, count: 28)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 * 1024 * 1024,
              let file = try? AVAudioFile(forReading: url), file.length > 0, file.length <= 30_000_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { return fallback }
        var values = Array(repeating: 0.0, count: 28)
        do {
            while file.framePosition < file.length {
                let start = file.framePosition
                try file.read(into: buffer)
                guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { return fallback }
                for index in 0..<Int(buffer.frameLength) {
                    let bin = min(27, Int((start + Int64(index)) * 28 / file.length))
                    values[bin] = max(values[bin], Double(abs(channel[index])))
                }
            }
            let peak = max(values.max() ?? 0, 0.001)
            return values.map { max(0.12, $0 / peak) }
        } catch { return fallback }
    }
}

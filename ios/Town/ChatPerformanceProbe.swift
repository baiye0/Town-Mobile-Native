#if DEBUG
import UIKit
import Combine

/// Opt-in diagnostics for isolated QA runs. Contains timings/counts only, never
/// message content, credentials or endpoint details. Inactive in normal use.
@MainActor final class ChatPerformanceProbe: NSObject {
    static let shared = ChatPerformanceProbe()
    private let enabled = ProcessInfo.processInfo.arguments.contains("--chat-performance-probe")
    private var link: CADisplayLink?
    private var observation: AnyCancellable?
    private var previous: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var storePublications = 0
    private var slowFrames: [[String: Double]] = []
    private var events: [[String: Any]] = []
    private var started: CFTimeInterval = 0
    func start(_ store: Store) {
        guard enabled, link == nil else { return }
        intervals = []; slowFrames = []; events = []; previous = 0; storePublications = 0; started = CACurrentMediaTime()
        observation = store.objectWillChange.sink { [weak self] in self?.storePublications += 1 }
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common); self.link = link
    }
    @objc private func frame(_ frame: CADisplayLink) {
        defer { previous = frame.timestamp }
        guard previous > 0, CACurrentMediaTime() - started > 1 else { return }
        let duration = (frame.timestamp - previous) * 1000
        intervals.append(duration)
        if duration > 50 { slowFrames.append(["elapsed": CACurrentMediaTime() - started, "duration_ms": duration]) }
    }
    func mark(_ event: String) {
        guard enabled, link != nil else { return }
        events.append(["elapsed": CACurrentMediaTime() - started, "event": event])
    }
    func stop() {
        guard link != nil else { return }
        link?.invalidate(); link = nil; observation = nil
        let sorted = intervals.sorted()
        let report: [String: Any] = ["samples": sorted.count,
            "p95_frame_ms": sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
            "max_frame_ms": sorted.last ?? 0,
            "frames_over_50ms": sorted.filter { $0 > 50 }.count,
            "frames_over_100ms": sorted.filter { $0 > 100 }.count,
            "store_publications": storePublications, "slow_frames": slowFrames, "events": events]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appending(path: "chat-performance.json"), options: .atomic)
        }
    }
}
#endif

import SwiftUI

@MainActor final class RunProgress: ObservableObject {
    @Published var process = ""
    @Published var activity = ""
}

struct ActiveChatRunView: View {
    @ObservedObject var progress: RunProgress
    let hasReply: Bool
    var body: some View {
        if !hasReply || !progress.process.isEmpty {
            ChatRunView(process: progress.process, activity: progress.activity, isActive: !hasReply)
        }
    }
}

/// Only opacity changes; waiting never changes row geometry or scroll position.
struct WaitingReplyBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle().fill(ClientTheme.secondary).frame(width: 5, height: 5)
                    .opacity(pulsing && !reduceMotion ? 0.45 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.65)
                        .repeatForever(autoreverses: true).delay(Double(index) * 0.14), value: pulsing)
            }
        }.frame(height: 20).padding(.horizontal, 16).padding(.vertical, 12)
            .background(ClientTheme.chatReply, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .ignore).accessibilityLabel("正在等待回复")
            .accessibilityIdentifier("waitingReplyBubble")
            .onAppear { pulsing = !reduceMotion }
            .onChange(of: reduceMotion) { pulsing = !$0 }
    }
}

/// The run exists before the first reply and keeps its place between the user
/// turn and its replies. Only progress supplied by the server is shown.
struct ChatRunView: View {
    let process: String
    let activity: String
    let isActive: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
                #if DEBUG
                ChatPerformanceProbe.shared.mark(expanded ? "process-open" : "process-close")
                #endif
            } label: {
                HStack(spacing: 8) {
                    if isActive { ProgressView().controlSize(.small) }
                    else { Image(systemName: "list.bullet.rectangle") }
                    Text(isActive ? (activity.isEmpty ? "思考中" : activity) : "思考与工具过程")
                    Spacer(minLength: 8)
                    if !process.isEmpty { Image(systemName: expanded ? "chevron.down" : "chevron.right") }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .disabled(process.isEmpty)
                .accessibilityIdentifier(isActive ? "activeRunDetails" : "completedRunDetails")
                .accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded {
                ProcessDetails(process: process)
            }
        }.font(.caption).foregroundStyle(ClientTheme.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: isActive) { if !$0 { expanded = false } }
    }
}

private struct ProcessDetails: View {
    let process: String
    @State private var chunks: [String] = []
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array((chunks.isEmpty ? [String(process.prefix(1200))] : chunks).enumerated()), id: \.offset) { index, chunk in
                    Text(chunk).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(index == 0 ? "runProcessDetails" : "runProcessDetails-\(index)")
                }
            }
        }.frame(height: 180).accessibilityIdentifier("runProcessScroll")
            .task(id: process) {
                let result = await ProcessTextParser.shared.chunks(process)
                guard !Task.isCancelled else { return }
                chunks = result
            }
    }
}

actor ProcessTextParser {
    static let shared = ProcessTextParser()
    func chunks(_ source: String) -> [String] {
        var chunks: [String] = [], start = source.startIndex
        while start < source.endIndex {
            guard !Task.isCancelled else { return [] }
            let end = source.index(start, offsetBy: 1200, limitedBy: source.endIndex) ?? source.endIndex
            chunks.append(String(source[start..<end])); start = end
        }
        return chunks
    }
}

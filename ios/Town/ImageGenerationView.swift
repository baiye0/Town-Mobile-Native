import SwiftUI

struct GeneratedMessageText: View, Equatable {
    let text: String
    let message: Message
    let foreground: Color
    let connection: Connection?
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.message.id == rhs.message.id && lhs.message.role == rhs.message.role &&
        lhs.message.sceneID == rhs.message.sceneID && lhs.message.streaming == rhs.message.streaming &&
        lhs.foreground == rhs.foreground && lhs.connection == rhs.connection
    }
    private var parts: [GenerationPart] {
        guard message.role == "being" else { return [GenerationPart(text: text)] }
        var seen = Set<String>()
        return ImageGeneration.parts(text).filter { part in
            guard part.receipt, let receipt = ImageGeneration.parse(part.text) else { return true }
            return seen.insert(receipt.being + receipt.jobs.map { "\($0.id ?? ""):\($0.request)" }.joined(separator: ",")).inserted
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.receipt {
                    if message.streaming == true {
                        Label("正在接收图片任务回执…", systemImage: "photo").font(.footnote)
                    } else if let receipt = ImageGeneration.parse(part.text) {
                        GenerationReceiptView(receipt: receipt, connection: connection)
                            .id("\(connection?.endpoint ?? "")|\(connection?.token ?? "")|\(message.id)|\(message.sceneID ?? "")|\(part.text)")
                    } else {
                        Text("图片回执格式无效，请让 Being 仅修正回执，不要重新生成。").font(.caption)
                        MarkdownText(text: part.text, foreground: foreground, fillsWidth: false)
                    }
                } else { MarkdownText(text: part.text, foreground: foreground, fillsWidth: false, imageReferences: MarkdownImages.definitions(text)) }
            }
        }
    }
}
private struct GenerationReceiptView: View {
    let receipt: GenerationReceipt
    let connection: Connection?
    @State private var snapshots: [Int: GenerationSnapshot] = [:]
    @State private var preview: String?
    private var images: [ChatImage] { receipt.jobs.flatMap { snapshots[$0.index]?.images ?? [] }.map { ChatImage(url: $0.url, label: $0.label) } }
    private var matched: Bool {
        guard let connection, connection.being == receipt.being, let url = URLComponents(string: connection.endpoint) else { return false }
        return url.scheme == "https" && url.host == "echo.beings.town" && (url.port == nil || url.port == 443)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("生成图片", systemImage: "photo.on.rectangle").font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text("\(receipt.jobs.count) 张").font(.caption).monospacedDigit()
            }.foregroundStyle(.secondary)
            if matched, let connection {
                ForEach(receipt.jobs, id: \.request) { job in
                    GenerationJobView(job: job, connection: connection, open: { preview = $0 }) { snapshots[job.index] = $0 }
                }
            } else { Text("回执与当前连接不匹配，或当前 Heart 未配置生图服务").font(.caption) }
        }
        .fullScreenCover(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            ImageGallery(images: images, initial: images.firstIndex { $0.url == preview } ?? 0)
        }
    }
}
private struct GenerationJobView: View {
    let job: GenerationJob
    let connection: Connection
    let open: (String) -> Void
    let update: (GenerationSnapshot) -> Void
    @State private var notice = "正在查询"
    @State private var snapshot: GenerationSnapshot?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GenerationJobCard(job: job, images: snapshot?.images ?? [], notice: notice, open: open)
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await poll()
        }
    }
    @MainActor private func poll() async {
        if job.submission == "rejected" { notice = "提交未受理：\(job.error ?? "未知原因")"; return }
        var failures = 0, resolved = job.id
        while !Task.isCancelled {
            do {
                let route = resolved ?? "by-request/\(job.request)"
                var request = URLRequest(url: URL(string: "https://beings.town/api/being-service/v1/generations/\(route)")!, timeoutInterval: 30)
                request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
                request.setValue(connection.being, forHTTPHeaderField: "X-Being-Id")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
                let data = try await ImageTransport.read(request, limit: 1024 * 1024)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PortalError.invalidResponse }
                let result = try ImageGeneration.snapshot(object, job: job)
                guard resolved == nil || resolved == result.id else { throw PortalError.invalidResponse }
                try Task.checkCancellation(); snapshot = result; update(result); resolved = result.id; failures = 0
                let now = Date().timeIntervalSince1970 * 1000
                notice = result.notice(now)
                guard let wait = result.wait(now) else { return }
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000))
            } catch {
                if Task.isCancelled { return }; failures += 1
                let permanent = (error as? ImageQueryError).map { [400, 401, 403, 404, 405, 409].contains($0.status) } ?? (error is PortalError)
                let again = !permanent && failures < 5
                notice = again ? "正在重新连接…" : "暂时无法获取图片"
                if !again { return }
                do { try await Task.sleep(nanoseconds: UInt64(min(2000 * pow(2, Double(failures - 1)), 30000) * 1_000_000)) } catch { return }
            }
        }
    }
}

/// The image is the primary content; successful jobs need no status or action row.
struct GenerationJobCard: View {
    let job: GenerationJob
    let images: [GenerationImage]
    let notice: String
    let open: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if images.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text(notice.replacingOccurrences(of: "，可重新查询", with: ""))
                }
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 96)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    RemoteImage(image: ChatImage(url: image.url, label: image.label), open: { open(image.url) }, inlineMaxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            Text(job.title).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(job.title)
        }
    }
}

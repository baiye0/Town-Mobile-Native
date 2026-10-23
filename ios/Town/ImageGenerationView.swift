import SwiftUI

struct GeneratedMessageText: View {
    let text: String
    let message: Message
    let foreground: Color
    @EnvironmentObject private var store: Store
    private var parts: [GenerationPart] {
        guard message.streaming != true && message.role == "being" else { return [GenerationPart(text: text)] }
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
                    if let receipt = ImageGeneration.parse(part.text) {
                        GenerationReceiptView(receipt: receipt, connection: store.connection)
                            .id("\(store.connection?.endpoint ?? "")|\(store.connection?.token ?? "")|\(message.id)|\(message.sceneID ?? "")|\(part.text)")
                    } else {
                        Text("图片回执格式无效，请修复回执后重试").font(.caption)
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
        VStack(alignment: .leading, spacing: 8) {
            if matched, let connection {
                ForEach(receipt.jobs, id: \.request) { job in
                    GenerationJobView(job: job, connection: connection) { snapshots[job.index] = $0 }
                    ForEach(Array((snapshots[job.index]?.images ?? []).enumerated()), id: \.offset) { _, image in
                        RemoteImage(image: ChatImage(url: image.url, label: image.label), open: { preview = image.url })
                    }
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
    let update: (GenerationSnapshot) -> Void
    @State private var notice = "正在查询"
    @State private var busy = false
    @State private var retry = 0
    var body: some View {
        VStack(alignment: .leading) {
            Text(job.title).font(.headline)
            HStack { if busy { ProgressView() }; Text(notice).font(.caption) }
            if !busy && job.submission != "rejected" { Button("重新查询") { retry += 1 }.font(.caption) }
        }.task(id: retry) { await poll() }
    }
    @MainActor private func poll() async {
        if job.submission == "rejected" { notice = "提交未受理：\(job.error ?? "未知原因")"; return }
        var failures = 0, resolved = job.id
        while !Task.isCancelled {
            busy = true
            do {
                let route = resolved ?? "by-request/\(job.request)"
                var request = URLRequest(url: URL(string: "https://beings.town/api/being-service/v1/generations/\(route)")!, timeoutInterval: 30)
                request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
                request.setValue(connection.being, forHTTPHeaderField: "X-Being-Id")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let data = try await ImageTransport.read(request, limit: 1024 * 1024)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PortalError.invalidResponse }
                let result = try ImageGeneration.snapshot(object, job: job)
                guard resolved == nil || resolved == result.id else { throw PortalError.invalidResponse }
                try Task.checkCancellation(); update(result); resolved = result.id; failures = 0
                let now = Date().timeIntervalSince1970 * 1000
                notice = result.notice(now); busy = false
                guard let wait = result.wait(now) else { return }
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000))
            } catch {
                if Task.isCancelled { return }; busy = false; failures += 1
                let permanent = (error as? ImageQueryError).map { [400, 401, 403, 404, 405, 409].contains($0.status) } ?? (error is PortalError)
                let again = !permanent && failures < 5
                notice = again ? "查询中断，正在重连…" : "暂时无法查询，请核对连接和回执后重新查询"
                if !again { return }
                do { try await Task.sleep(nanoseconds: UInt64(min(2000 * pow(2, Double(failures - 1)), 30000) * 1_000_000)) } catch { return }
            }
        }
    }
}

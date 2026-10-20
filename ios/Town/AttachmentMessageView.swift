import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import ImageIO

struct AttachmentMessageView: View {
    let message: Message
    var foreground: Color
    var attachmentCards = false
    @EnvironmentObject private var store: Store
    @State private var files: [PendingAttachment] = []
    @State private var text: String?
    @State private var error: String?
    @State private var preview: URL?
    @State private var previewImage: UIImage?
    @State private var imageURL: URL?
    @State private var remoteImages: [String: UIImage] = [:]
    @State private var remoteFiles: [String: URL] = [:]
    @State private var failedImages: Set<String> = []
    @State private var loadingDetails = true
    @State private var working = false
    private var references: [String] {
        let regex = try! NSRegularExpression(pattern: "(?m)^\\[attachment-message:v1:(msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*)\\]\\r?$")
        guard let match = regex.matches(in: message.text, range: NSRange(message.text.startIndex..., in: message.text)).last, let range = Range(match.range(at: 1), in: message.text) else { return [] }
        return message.text[range].split(separator: ",").map(String.init)
    }
    private var loadIdentity: String {
        let metadata = (message.files ?? []).map {
            "\($0.id)|\($0.attachmentID ?? "")|\($0.resultID ?? "")|\($0.path)"
        }.joined(separator: ",")
        return "\(store.connection?.endpoint ?? "")|\(message.id)|\(references.joined(separator: ","))|\(metadata)"
    }
    var body: some View {
        VStack(alignment: attachmentCards ? .trailing : .leading, spacing: 10) {
            // The Muse/Town layout gives a user attachment its own bubble and
            // renders the original prompt in a separate conversation bubble.
            // Plain user messages still render their text in this shared view.
            if message.role != "user" || (message.files?.isEmpty != false && references.isEmpty) {
                MarkdownText(text: text ?? (references.isEmpty ? message.text.replacingOccurrences(of: NativeUI.context, with: "") : "附件消息"), foreground: foreground, fillsWidth: false).environment(\.nativeUIScene, message.sceneID ?? "sbs")
            }
            ForEach(files) { file in
                if file.mime.hasPrefix("image/") {
                    Button { Task { await open(file) } } label: {
                        if let image = localImage(file) ?? remoteImages[file.id] {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(maxWidth: 260, maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.12))
                                .frame(width: 220, height: 160)
                                .overlay {
                                    if failedImages.contains(file.id) {
                                        Label("图片加载失败，点击重试", systemImage: "arrow.clockwise").font(.caption).padding()
                                    } else { ProgressView("正在加载图片").font(.caption).tint(foreground) }
                                }
                        }
                    }.buttonStyle(.plain).disabled(working).accessibilityLabel("查看图片")
                } else if file.mime.hasPrefix("audio/") {
                    AttachmentAudioView(file: file, foreground: attachmentCards ? .white : foreground, loadURL: { try await mediaURL(file) }, loadTranscript: {
                        guard let c = store.connection, let id = file.attachmentID, let version = file.resultID else { return "" }
                        let value = try await store.parsedText(c, id: id, version: version)
                        try Task.checkCancellation()
                        guard store.connection == c else { throw CancellationError() }
                        return AudioTranscript.display(value)
                    }).id("\(store.connection?.endpoint ?? "")|\(file.id)")
                        .padding(attachmentCards ? 16 : 0)
                        .background(attachmentCards ? ClientTheme.chatSent : .clear, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    VStack(alignment: .leading) {
                        Button { Task { await open(file) } } label: { Label(file.name, systemImage: "doc").lineLimit(2) }.disabled(working)
                    }.padding(attachmentCards ? 16 : 10)
                        .foregroundStyle(attachmentCards ? .white : foreground)
                        .background(attachmentCards ? ClientTheme.chatSent : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: attachmentCards ? 22 : 10))
                }
            }
            if loadingDetails && files.isEmpty && !references.isEmpty { ProgressView("正在加载附件").font(.caption).tint(foreground) }
            // Older saved replies can still carry process details. New runs are
            // displayed independently beneath their initiating user turn.
            if message.role != "user", let process = message.process, !process.isEmpty { DisclosureGroup("思考与工具过程") { Text(process).font(.caption).textSelection(.enabled) }.font(.caption) }
            if working { ProgressView() }
            if let error { Text(error).font(.caption); Button("重新读取附件") { Task { await load() } }.font(.caption) }
        }.foregroundStyle(foreground)
        .task(id: loadIdentity) { await load() }
        .task(id: files.map { "\($0.id)|\($0.attachmentID ?? "")|\($0.path)" }.joined(separator: ",")) { await loadRemoteImages() }
            .quickLookPreview($preview)
            .sheet(isPresented: Binding(get: { previewImage != nil }, set: { if !$0 { previewImage = nil } })) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    if let previewImage {
                        Image(uiImage: previewImage).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea(.container, edges: .all)
                    }
                    HStack {
                    if let imageURL {
                        ShareLink(item: imageURL) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white).frame(width: 44, height: 44)
                                .background(.black.opacity(0.65), in: Circle())
                        }.accessibilityLabel("保存或分享图片")
                    }
                    Button { previewImage = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(.black.opacity(0.65), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("关闭图片")
                    }.padding(16)
                }
                .beingPresentationBackground(.black)
            }
    }
    private func localImage(_ file: PendingAttachment) -> UIImage? {
        guard let local = resolvedLocalFile(file), local.mime.hasPrefix("image/") else { return nil }
        return thumbnail(URL.documentsDirectory.appending(path: "attachments/" + local.path))
    }
    private func thumbnail(_ url: URL) -> UIImage? {
        if let cached = AttachmentThumbnailCache.images.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { return nil }
        let thumbnail = UIImage(cgImage: image)
        AttachmentThumbnailCache.images.setObject(thumbnail, forKey: url as NSURL,
                                                 cost: image.bytesPerRow * image.height)
        return thumbnail
    }
    private func load() async {
        loadingDetails = true
        defer { loadingDetails = false }
        files = message.files ?? []; error = nil
        guard !references.isEmpty, let c = store.connection else { return }
        do {
            var parts: [PendingAttachment] = [], texts: [String] = []
            let localFiles = Dictionary(uniqueKeysWithValues: files.compactMap { file in file.attachmentID.map { ($0, file) } })
            for id in references {
                let data = try await store.attachmentJSON(c, "/api/attachment-messages/\(id)")
                guard data["message_id"] as? String == id, data["version"] as? Int == 1, data["scene_id"] as? String == message.sceneID else { throw PortalError.invalidResponse }
                for part in data["parts"] as? [[String: Any]] ?? [] {
                    if part["type"] as? String == "text" { texts.append(part["text"] as? String ?? "") }
                    else if let aid = part["attachment_id"] as? String, DeliveryRules.safeID(aid) {
                        let local = localFiles[aid]
                        parts.append(PendingAttachment(id: local?.id ?? aid, name: part["name"] as? String ?? local?.name ?? "附件", mime: part["mime"] as? String ?? local?.mime ?? "application/octet-stream", path: local?.path ?? "", size: part["size"] as? Int ?? local?.size ?? 0, attachmentID: aid, resultID: (part["parse_result_id"] as? String).flatMap { DeliveryRules.safeID($0) ? $0 : nil }))
                    }
                }
            }
            try Task.checkCancellation(); guard store.connection == c else { return }; files = parts; text = texts.joined(separator: "\n\n")
        } catch { if !Task.isCancelled { self.error = "附件详情读取失败，原记录已保留。" } }
    }
    private func loadRemoteImages() async {
        guard let c = store.connection else { return }
        for file in files where file.mime.hasPrefix("image/") && localImage(file) == nil && remoteImages[file.id] == nil {
            guard let id = file.attachmentID, file.size <= 50 * 1024 * 1024 else { failedImages.insert(file.id); continue }
            failedImages.remove(file.id)
            do {
                let temporary = try await store.downloadAttachment(c, id: id, name: file.name)
                guard let image = thumbnail(temporary) else { throw PortalError.invalidResponse }
                guard store.connection == c else { return }
                remoteFiles[file.id] = temporary
                remoteImages[file.id] = image
            } catch { if Task.isCancelled { return }; failedImages.insert(file.id) }
        }
    }
    private func resolvedLocalFile(_ file: PendingAttachment) -> PendingAttachment? {
        if !file.path.isEmpty { return file }
        return message.files?.first { $0.attachmentID == file.attachmentID && !$0.path.isEmpty }
    }
    private func mediaURL(_ file: PendingAttachment) async throws -> URL {
        if let cached = remoteFiles[file.id], FileManager.default.fileExists(atPath: cached.path) { return cached }
        if let local = resolvedLocalFile(file) {
            let url = URL.documentsDirectory.appending(path: "attachments/" + local.path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        guard let c = store.connection, let id = file.attachmentID else { throw PortalError.invalidResponse }
        guard file.size <= 50 * 1024 * 1024 else { throw PortalError.server("此文件超过移动端 50 MB 预览上限。") }
        return try await store.downloadAttachment(c, id: id, name: file.name)
    }
    private func open(_ file: PendingAttachment) async {
        working = true; error = nil; defer { working = false }
        do {
            let url = try await mediaURL(file)
            if file.mime.hasPrefix("image/"), let image = UIImage(contentsOfFile: url.path) {
                remoteFiles[file.id] = url; remoteImages[file.id] = thumbnail(url)
                failedImages.remove(file.id); imageURL = url; previewImage = image
            }
            else {
                let directory = URL.cachesDirectory.appending(path: "previews/" + UUID().uuidString, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let name = URL(fileURLWithPath: file.name).lastPathComponent
                let destination = directory.appendingPathComponent(name.isEmpty || name == "." || name == ".." ? "附件" : name)
                try FileManager.default.copyItem(at: url, to: destination)
                preview = destination
            }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

// Imported attachment paths are immutable UUIDs. Reuse their bounded previews
// while new tokens arrive instead of decoding images during each body update.
@MainActor private enum AttachmentThumbnailCache {
    static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
}

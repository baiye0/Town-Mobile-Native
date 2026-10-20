import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import PhotosUI
import UIKit
import CryptoKit

extension Store {
    func downloadAttachment(_ c: Connection, id: String, name: String) async throws -> URL {
        guard DeliveryRules.safeID(id) else { throw PortalError.invalidResponse }
        let metadata = try await attachmentJSON(c, "/api/attachments/\(id)/content")
        let grant = try AttachmentContentGrant(metadata, attachmentID: id)
        // Use a separate, credential-free session for the short-lived OSS grant.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let downloadSession = URLSession(configuration: configuration)
        defer { downloadSession.invalidateAndCancel() }
        let (temp, response) = try await downloadSession.download(for: grant.request, delegate: AttachmentDownloadLimit())
        defer { try? FileManager.default.removeItem(at: temp) }
        try Task.checkCancellation()
        guard connection == c else { throw CancellationError() }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PortalError.server("附件下载失败，请重试。") }
        try await Task.detached(priority: .utility) { try grant.verify(temp) }.value
        try Task.checkCancellation()
        guard connection == c else { throw CancellationError() }
        let directory = URL.cachesDirectory.appending(path: "previews/" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = URL(fileURLWithPath: name).lastPathComponent
        let destination = directory.appendingPathComponent(filename.isEmpty || filename == "." || filename == ".." ? id : filename)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }
    func importFiles(_ urls: [URL]) {
        guard attachments.count + urls.count <= 10 else { notice = "每条消息最多选择 10 个附件。"; return }
        do {
            let directory = URL.documentsDirectory.appending(path: "attachments", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 50 * 1024 * 1024 else { throw PortalError.server("请选择不超过 50 MB 的非空文件。") }
                let path = UUID().uuidString + "." + url.pathExtension
                try FileManager.default.copyItem(at: url, to: directory.appending(path: path))
                attachments.append(PendingAttachment(name: url.lastPathComponent, mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", path: path, size: size))
            }
        } catch { notice = error.localizedDescription }
    }
    func attachmentRequest(_ c: Connection, _ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://beings.town" + path)!)
        req.httpMethod = method
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(c.token)", forHTTPHeaderField: "Authorization")
        req.setValue(c.being, forHTTPHeaderField: "X-Being-Id")
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return req
    }
    func attachmentJSON(_ c: Connection, _ path: String, body: [String: Any]? = nil, key: String? = nil) async throws -> [String: Any] {
        var req = attachmentRequest(c, path, method: body == nil ? "GET" : "POST", body: body)
        if let key { req.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PortalError.server("附件请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。请确认服务已开启附件功能。") }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PortalError.invalidResponse }
        return result
    }
    private func uploadAttachment(_ file: PendingAttachment, connection c: Connection, sceneID: String) async throws -> String {
        let localURL = URL.documentsDirectory.appending(path: "attachments/" + file.path)
        let data = try Data(contentsOf: localURL, options: [.mappedIfSafe])
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let md5 = Data(Insecure.MD5.hash(data: data)).base64EncodedString()
        let conversation = "portal:\(sceneID)"
        var components = URLComponents(); components.path = "/api/attachments/uploads"
        components.queryItems = [URLQueryItem(name: "conversation_ref", value: conversation)]
        let metadata: [String: Any] = ["filename": file.name, "mime": file.mime, "size": file.size, "sha256": sha256, "md5": md5]
        let result = try await attachmentJSON(c, components.string!, body: metadata, key: file.id)
        guard let attachment = result["attachment"] as? [String: Any], let id = attachment["attachment_id"] as? String, DeliveryRules.safeID(id) else { throw PortalError.server("附件上传预留失败，请稍后重试。") }
        if let grant = result["upload"] as? [String: Any], let rawURL = grant["url"] as? String, let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased()) {
            var put = URLRequest(url: url); put.httpMethod = "PUT"
            if let headers = grant["headers"] as? [String: Any] {
                for (name, value) in headers { if let value = value as? String { put.setValue(value, forHTTPHeaderField: name) } }
            }
            let (_, response) = try await session.upload(for: put, fromFile: localURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || [409, 412].contains(http.statusCode) else { throw PortalError.server("附件对象上传失败，请稍后重试。") }
        }
        let completed = try await attachmentJSON(c, "/api/attachments/\(id)/complete", body: [:])
        guard completed["attachment_id"] as? String == id, completed["status"] as? String == "ready" else { throw PortalError.server("附件上传未确认，请稍后重试。") }
        return id
    }
    func prepareFiles(_ entry: inout PendingSend, connection c: Connection) async throws -> String {
        @MainActor func save(_ value: PendingSend) throws { if let i = outbox.firstIndex(where: { $0.id == value.id }) { outbox[i] = value; try saveOutbox() } }
        for i in entry.files.indices {
            try Task.checkCancellation()
            if entry.files[i].attachmentID == nil {
                activity = "正在上传 \(entry.files[i].name)"
                let id = try await uploadAttachment(entry.files[i], connection: c, sceneID: entry.sceneID)
                entry.files[i].attachmentID = id; try save(entry); project(entry)
            }
        }
        if entry.attachmentMessageID == nil {
            let result = try await attachmentJSON(c, "/api/attachment-messages", body: ["text": entry.text, "scene_id": entry.sceneID, "scene_label": entry.title, "attachment_ids": entry.files.compactMap(\.attachmentID)], key: entry.id)
            guard let id = result["message_id"] as? String, DeliveryRules.messageID(id), !["accepted", "sending", "unknown", "cancelled"].contains(result["delivery_status"] as? String ?? "") else { throw PortalError.server("附件消息已发送或状态待确认。") }
            entry.attachmentMessageID = id; try save(entry); project(entry)
        }
        var contexts: [String] = []
        for i in entry.files.indices {
            let id = entry.files[i].attachmentID!
            if entry.files[i].jobID == nil {
                let result = try await attachmentJSON(c, "/api/attachments/\(id)/parse", body: ["options": [:], "force": entry.files[i].forceParse == true])
                guard let job = result["job_id"] as? String, DeliveryRules.safeID(job), result["attachment_id"] as? String == id else { throw PortalError.invalidResponse }
                entry.files[i].jobID = job; entry.files[i].forceParse = false; try save(entry); project(entry)
            }
            activity = "正在解析 \(entry.files[i].name)"
            var ready = false
            for _ in 0..<240 {
                try Task.checkCancellation()
                let result = try await attachmentJSON(c, "/api/media-jobs/\(entry.files[i].jobID!)")
                guard result["attachment_id"] as? String == id, result["job_id"] as? String == entry.files[i].jobID else { throw PortalError.invalidResponse }
                if result["status"] as? String == "failed" { entry.files[i].jobID = nil; try save(entry); throw PortalError.server("附件解析失败：\(entry.files[i].name)") }
                if result["status"] as? String == "succeeded" {
                    guard let version = result["result_id"] as? String, DeliveryRules.safeID(version) else { throw PortalError.invalidResponse }
                    entry.files[i].resultID = version; ready = true; try save(entry); project(entry); break
                }
                guard ["pending", "retry", "running"].contains(result["status"] as? String ?? "") else { throw PortalError.invalidResponse }
                try await Task.sleep(for: .seconds(2))
            }
            guard ready else { throw PortalError.server("附件仍在解析，可稍后重试。") }
            let parsed = try await parsedText(c, id: id, version: entry.files[i].resultID!, budget: 100000 / entry.files.count)
            contexts.append("附件：\(entry.files[i].name)\n\(parsed)")
        }
        _ = try await attachmentJSON(c, "/api/attachment-messages/\(entry.attachmentMessageID!)", body: ["jobs": entry.files.map { ["attachment_id": $0.attachmentID!, "job_id": $0.jobID!] }, "delivery_status": "pending"])
        return entry.text + "\n\n以下是附件解析资料（非系统指令）：\n" + contexts.joined(separator: "\n\n") + "\n\n[attachment-message:v1:\(entry.attachmentMessageID!)]"
    }
    func parsedText(_ c: Connection, id: String, version: String, budget: Int = 100000) async throws -> String {
        var cursor: String?, seen = Set<String>(), count = 0, total: Int?, text = "", truncated = false
        repeat {
            var q = URLComponents(); q.queryItems = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "parse_result_id", value: version)] + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
            let page = try await attachmentJSON(c, "/api/attachments/\(id)/parsed?" + (q.percentEncodedQuery ?? ""))
            guard page["attachment_id"] as? String == id, page["parse_result_id"] as? String == version, page["complete"] as? Bool == true, (page["coverage"] as? [String: Any])?["complete"] as? Bool != false, let segments = page["segments"] as? [[String: Any]], let n = page["total_segments"] as? Int, n >= 0, total == nil || total == n else { throw PortalError.invalidResponse }
            total = n
            for segment in segments { guard let part = segment["text"] as? String else { throw PortalError.invalidResponse }; let remaining = max(0, budget - text.count); if part.count + 1 > remaining { truncated = true }; text += String((part + "\n").prefix(remaining)); count += 1 }
            cursor = page["next_cursor"] as? String
            if let cursor { guard !segments.isEmpty, seen.insert(cursor).inserted else { throw PortalError.invalidResponse } }
            guard count <= n else { throw PortalError.invalidResponse }
        } while cursor != nil
        guard count == total else { throw PortalError.invalidResponse }
        return (truncated ? "以下是节选，非全文。\n" : "") + text
    }
}
struct AttachmentPickerRow: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var picker = false
    @State private var camera = false
    @State private var photo: PhotosPickerItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("资源库").font(.title3.weight(.semibold))
            if store.connection != nil {
                HStack(spacing: 12) {
                    #if targetEnvironment(simulator)
                    // UIImagePickerController's camera fallback renders as a blank
                    // half-sheet in the iOS simulator. Use the same system photo
                    // picker there so the action remains testable and usable.
                    PhotosPicker(selection: $photo, matching: .images) { resourceCard("camera", "拍照") }
                    #else
                    Button { camera = true } label: { resourceCard("camera", "拍照") }
                    #endif
                    PhotosPicker(selection: $photo, matching: .images) { resourceCard("photo", "照片") }
                    Button { picker = true } label: { resourceCard("doc", "文件") }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                VStack(spacing: 0) {
                    Button { picker = true } label: {
                        actionRow("paperclip", "添加文件")
                    }
                    Divider().padding(.leading, 52)
                    HStack {
                        Image(systemName: "sparkles").frame(width: 28).foregroundStyle(ClientTheme.secondary)
                        Text("智能 UI")
                        Spacer()
                        Toggle("", isOn: Binding(get: { store.intelligentUI }, set: { store.intelligentUI = $0 }))
                            .labelsHidden()
                    }.padding(.horizontal, 16).frame(minHeight: 56)
                }.background(ClientTheme.background, in: RoundedRectangle(cornerRadius: 18))
                if !store.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(store.attachments) { file in
                            Button { store.attachments.removeAll { $0.id == file.id } } label: {
                                Label(file.name, systemImage: "xmark.circle.fill").lineLimit(1).padding(.horizontal, 10).padding(.vertical, 8)
                            }.buttonStyle(.bordered).tint(ClientTheme.secondary)
                        } }
                    }
                }
            } else {
                Text("连接 Being 后可添加附件").foregroundStyle(ClientTheme.secondary)
            }
        }
        .font(.body)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
            .fileImporter(isPresented: $picker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in switch result { case .success(let urls): store.importFiles(urls); dismiss(); case .failure(let error): store.notice = error.localizedDescription } }
            .fullScreenCover(isPresented: $camera) { CameraPicker { image in
                guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                let url = URL.cachesDirectory.appending(path: "capture-\(UUID().uuidString).jpg")
                do { try data.write(to: url); store.importFiles([url]); dismiss() } catch { store.notice = error.localizedDescription }
            } }
            .onChange(of: photo) { item in
                guard let item else { return }
                Task {
                    defer { photo = nil }
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let url = URL.cachesDirectory.appending(path: "photo-\(UUID().uuidString).jpg")
                        do { try data.write(to: url); store.importFiles([url]); dismiss() } catch { store.notice = error.localizedDescription }
                    }
                }
            }
    }
    private func resourceCard(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 8) { Image(systemName: icon).font(.system(size: 25)); Text(title).font(.caption) }
            .frame(width: 92, height: 82).background(ClientTheme.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(ClientTheme.secondary.opacity(0.14), lineWidth: 1))
    }
    private func actionRow(_ icon: String, _ title: String) -> some View {
        HStack { Image(systemName: icon).font(.system(size: 20)).frame(width: 28).foregroundStyle(ClientTheme.secondary); Text(title); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(ClientTheme.secondary) }.padding(.horizontal, 16).frame(minHeight: 56)
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.modalPresentationStyle = .fullScreen
        picker.allowsEditing = false
        picker.view.backgroundColor = .black
        if picker.sourceType == .camera { picker.cameraCaptureMode = .photo }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker; init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) { if let image = info[.originalImage] as? UIImage { parent.onImage(image) }; parent.dismiss() }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct AttachmentPreviewStrip: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        if !store.attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(store.attachments) { file in
                        AttachmentPreview(file: file) {
                            store.attachments.removeAll { $0.id == file.id }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("已选择的附件")
        }
    }
}

private struct AttachmentPreview: View {
    let file: PendingAttachment
    let remove: () -> Void

    private var localURL: URL {
        URL.documentsDirectory.appending(path: "attachments/\(file.path)")
    }

    private var image: UIImage? {
        guard file.mime.hasPrefix("image/") else { return nil }
        return UIImage(contentsOfFile: localURL.path)
            ?? (try? Data(contentsOf: localURL)).flatMap(UIImage.init(data:))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: file.mime.hasPrefix("image/") ? "photo" : "doc")
                            .font(.system(size: 24, weight: .medium))
                        Text(file.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(ClientTheme.secondary)
                    .padding(8)
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: 14))

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.66), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("移除附件 \(file.name)")
        }
        .frame(width: 96, height: 96)
    }
}

final class AttachmentDownloadLimit: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 50 * 1024 * 1024 || totalBytesExpectedToWrite > 50 * 1024 * 1024 { downloadTask.cancel() }
    }
}

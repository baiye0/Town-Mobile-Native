import SwiftUI
import ImageIO

struct ChatImage: Equatable { let url: String; let label: String }

final class ImageTransportDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var remaining: Int
    init(image: Bool) { remaining = image ? 5 : 0 }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard remaining > 0, let url = request.url, ImageTransport.validURL(url.absoluteString) else { completionHandler(nil); return }
        remaining -= 1
        var clean = URLRequest(url: url, timeoutInterval: 30)
        clean.setValue("image/*", forHTTPHeaderField: "Accept")
        completionHandler(clean)
    }
}
enum ImageTransport {
    static func validURL(_ raw: String) -> Bool {
        guard raw.count <= 16384, let url = URL(string: raw) else { return false }
        return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }
    static func read(_ request: URLRequest, limit: Int, image: Bool = false) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: ImageTransportDelegate(image: image), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw PortalError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ImageQueryError(status: http.statusCode) }
        guard response.expectedContentLength <= limit else { throw PortalError.invalidResponse }
        if image, !["image/png", "image/jpeg", "image/gif", "image/webp", "image/avif"].contains(response.mimeType ?? "") { throw PortalError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            if data.count % 16384 == 0 { try Task.checkCancellation() }
            guard data.count < limit else { throw PortalError.invalidResponse }; data.append(byte)
        }
        return data
    }
    static func imageBytes(_ raw: String) async throws -> Data {
        if raw.hasPrefix("data:") {
            guard raw.utf8.count <= 50 * 1024 * 1024 * 4 / 3 + 128,
                  let comma = raw.firstIndex(of: ","), ["data:image/png;base64", "data:image/jpeg;base64", "data:image/gif;base64", "data:image/webp;base64", "data:image/avif;base64"].contains(String(raw[..<comma])),
                  let data = Data(base64Encoded: String(raw[raw.index(after: comma)...])), data.count <= 50 * 1024 * 1024 else { throw PortalError.invalidResponse }
            return data
        }
        guard validURL(raw), let url = URL(string: raw) else { throw PortalError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 30); request.setValue("image/*", forHTTPHeaderField: "Accept")
        return try await read(request, limit: 50 * 1024 * 1024, image: true)
    }
}
struct ImageQueryError: Error { let status: Int }

struct RemoteImage: View {
    let image: ChatImage
    var open: (() -> Void)? = nil
    var fullScreen = false
    var inlineMaxHeight: CGFloat = 260
    @State private var bitmap: UIImage?
    @State private var failed = false
    @State private var retry = 0
    @State private var preview = false
    @State private var scale: CGFloat = 1
    @GestureState private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pan: CGSize = .zero
    var body: some View {
        Group {
            if let bitmap {
                Image(uiImage: bitmap).resizable().scaledToFit()
                    .scaleEffect(fullScreen ? max(1, min(5, scale * zoom)) : 1)
                    .offset(fullScreen && scale > 1 ? CGSize(width: offset.width + pan.width, height: offset.height + pan.height) : .zero)
                    .gesture(MagnificationGesture().updating($zoom) { value, state, _ in state = value }.onEnded { scale = max(1, min(5, scale * $0)); if scale == 1 { offset = .zero } }, including: fullScreen ? .all : .none)
                    .simultaneousGesture(DragGesture().updating($pan) { value, state, _ in state = value.translation }.onEnded { offset.width += $0.translation.width; offset.height += $0.translation.height }, including: fullScreen && scale > 1 ? .all : .none)
                    .onTapGesture { if !fullScreen { if let open { open() } else { preview = true } } }
                    .accessibilityLabel(image.label.isEmpty ? "查看图片" : image.label)
            } else if failed { Button("图片加载失败，点击重试") { retry += 1 } }
            else { ProgressView("正在加载图片") }
        }.frame(maxWidth: .infinity, minHeight: 140, maxHeight: fullScreen ? .infinity : inlineMaxHeight).clipped()
            .task(id: "\(image.url)|\(retry)") {
                bitmap = nil; failed = false
                do {
                    let data = try await ImageTransport.imageBytes(image.url)
                    let maximumSize = fullScreen ? 2048 : 1024
                    let decoded = await Task.detached(priority: .utility) { () -> CGImage? in
                        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximumSize] as CFDictionary)
                    }.value
                    try Task.checkCancellation()
                    guard let decoded else { throw PortalError.invalidResponse }; bitmap = UIImage(cgImage: decoded)
                } catch { if !Task.isCancelled { failed = true } }
            }
            .fullScreenCover(isPresented: $preview) { ImageGallery(images: [image], initial: 0) }
    }
}

struct ImageGallery: View {
    let images: [ChatImage]
    let initial: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    private var index: Int { images.firstIndex { $0.url == selected } ?? min(initial, images.count - 1) }
    var body: some View {
        VStack {
            HStack { Text("\(index + 1) / \(images.count)"); Spacer(); Button("关闭") { dismiss() } }.padding()
            if !images.isEmpty { RemoteImage(image: images[index], fullScreen: true).id(images[index].url) }
            Spacer(minLength: 0)
            HStack {
                Button("上一张") { selected = images[index - 1].url }.disabled(index <= 0)
                Spacer()
                Button("下一张") { selected = images[index + 1].url }.disabled(index >= images.count - 1)
            }.padding()
        }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
    }
}

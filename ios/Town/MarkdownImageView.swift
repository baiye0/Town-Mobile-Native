import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct MarkdownImageView: View {
    let alt: String
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var preview: ImagePreviewItem?
    @State private var original: URL?
    private var title: String { alt.isEmpty ? "图片" : alt }

    var body: some View {
        Button {
            if image != nil, let original { preview = ImagePreviewItem(url: original, title: title) }
            else if failed { attempt += 1 }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(ClientTheme.surface)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().padding(4)
                    } else if failed {
                        Label("图片加载失败，点击重试", systemImage: "arrow.clockwise")
                            .font(.footnote).padding(16)
                    } else {
                        ProgressView("正在加载图片").font(.footnote)
                    }
                }.frame(height: 200).frame(maxWidth: 360).clipShape(RoundedRectangle(cornerRadius: 12))
                if !alt.isEmpty { Text(alt).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }.foregroundStyle(ClientTheme.text)
        }.buttonStyle(.plain)
            .accessibilityLabel(image != nil ? "查看图片：\(title)" : failed ? "重试图片：\(title)" : "正在加载图片：\(title)")
            .accessibilityIdentifier("markdownImage")
            .task(id: "\(url.absoluteString)|\(attempt)") {
                image = nil; failed = false
                do {
                    let loaded = try await MarkdownImageLoader.load(url)
                    try Task.checkCancellation()
                    image = loaded.image; original = loaded.url
                } catch {
                    if !Task.isCancelled { failed = true }
                }
            }
            .fullScreenCover(item: $preview) { ImagePreview(item: $0) }
    }
}

enum MarkdownImageLoader {
    final class Asset {
        let image: UIImage; let url: URL
        init(image: UIImage, url: URL) { self.image = image; self.url = url }
    }
    static let cache: NSCache<NSURL, Asset> = {
        let cache = NSCache<NSURL, Asset>()
        cache.countLimit = 40; cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()
    // Image links carry their own authorization. Never attach the Being token or cookies.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
    static func load(_ url: URL) async throws -> Asset {
        if let asset = cache.object(forKey: url as NSURL), FileManager.default.fileExists(atPath: asset.url.path) { return asset }
        let (bytes, response) = try await session.bytes(from: url)
        let limit = 20 * 1024 * 1024
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.expectedContentLength <= limit else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        let image = UIImage(cgImage: thumbnail)
        let folder = URL.cachesDirectory.appending(path: "markdown-images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = (CGImageSourceGetType(source) as String?).flatMap { UTType($0)?.preferredFilenameExtension } ?? "png"
        let original = folder.appendingPathComponent("图片-" + UUID().uuidString + "." + ext)
        try data.write(to: original, options: .atomic)
        let asset = Asset(image: image, url: original)
        cache.setObject(asset, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
        // Reclaim previous-session downloads after a day; never prune a newly opened preview.
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               date.timeIntervalSinceNow < -86400 { try? FileManager.default.removeItem(at: file) }
        }
        return asset
    }
}

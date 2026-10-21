import SwiftUI
import UIKit
import Photos
import UniformTypeIdentifiers
import ImageIO

struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

/// Both attachment and Markdown images use the original local file for export.
struct ImagePreview: View {
    let item: ImagePreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var exporting = false
    @State private var document: ImageFileDocument?
    @State private var saving = false
    @State private var notice: String?
    @State private var zoom = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image { ZoomableImage(image: image, zoom: $zoom).accessibilityIdentifier("imagePreviewCanvas") }
                else { ProgressView("正在读取图片").tint(.white).foregroundStyle(.white) }
            }
            .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { Task { await savePhoto() } } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
                        Button {
                            do { document = try ImageFileDocument(url: item.url); exporting = true }
                            catch { notice = "读取原图失败，请重试。" }
                        } label: { Label("保存到文件", systemImage: "folder") }
                        ShareLink(item: item.url) { Label("分享图片", systemImage: "square.and.arrow.up") }
                    } label: { Label("保存或分享图片", systemImage: "square.and.arrow.down") }
                    .disabled(image == nil || saving)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(zoom > 1.01 ? "适合屏幕" : "放大图片") { zoom = zoom > 1.01 ? 1 : 2.5 }
                        .disabled(image == nil).accessibilityValue("\(Int(zoom * 100))%")
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .toolbarBackground(.black, for: .navigationBar, .bottomBar)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .fileExporter(isPresented: $exporting, document: document, contentType: document?.type ?? .image,
                          defaultFilename: item.url.lastPathComponent) { result in
                if case .failure = result { notice = "保存失败，请重试。" }
            }
            .alert("图片", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("好") { notice = nil }
            } message: { Text(notice ?? "") }
            .task {
                // Decode a bounded display image; export always keeps original bytes.
                guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 4096
                      ] as CFDictionary) else { notice = "无法读取这张图片，请返回后重试。"; return }
                image = UIImage(cgImage: cg)
            }
        }.preferredColorScheme(.dark)
    }
    @MainActor private func savePhoto() async {
        saving = true; defer { saving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            notice = "未获得添加照片权限。你可以在系统设置中允许，或选择“保存到文件”。"; return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: item.url)
            }
            notice = "已保存到相册"
        } catch { notice = "保存到相册失败，请重试或选择“保存到文件”。" }
    }
}

struct ImageFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.image] }
    let data: Data
    let type: UTType
    init(url: URL) throws {
        data = try Data(contentsOf: url)
        type = UTType(filenameExtension: url.pathExtension) ?? .image
    }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes; type = configuration.contentType
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var zoom: Double
    func makeUIView(context: Context) -> ImageZoomScrollView {
        let view = ImageZoomScrollView()
        view.imageView.image = image
        view.changed = { value in
            if abs(zoom - value) > 0.01 { DispatchQueue.main.async { zoom = value } }
        }
        return view
    }
    func updateUIView(_ view: ImageZoomScrollView, context: Context) {
        if view.imageView.image !== image { view.imageView.image = image; view.resetLayout() }
        if !view.isZooming && abs(Double(view.zoomScale) - zoom) > 0.02 { view.setZoomScale(zoom, animated: true) }
    }
}

private final class ImageZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var changed: ((Double) -> Void)?
    private var fittedSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; minimumZoomScale = 1; maximumZoomScale = 8
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        backgroundColor = .black; bouncesZoom = true
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2; addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func resetLayout() { fittedSize = .zero; setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize, bounds.width > 0, bounds.height > 0, let image = imageView.image {
            fittedSize = bounds.size
            setZoomScale(1, animated: false)
            let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * ratio, height: image.size.height * ratio))
            contentSize = imageView.bounds.size
        }
        centerImage()
    }
    private func centerImage() {
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0, (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(); changed?(Double(zoomScale)) }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 { setZoomScale(1, animated: true) }
        else {
            let point = gesture.location(in: imageView), scale: CGFloat = 2.5
            zoom(to: CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2,
                            width: bounds.width / scale, height: bounds.height / scale), animated: true)
        }
    }
}

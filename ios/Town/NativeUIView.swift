import SwiftUI
import WebKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

private struct NativeUISceneKey: EnvironmentKey { static let defaultValue = "" }
private struct NativeUIMessageKey: EnvironmentKey { static let defaultValue = "" }
extension EnvironmentValues {
    var nativeUIScene: String { get { self[NativeUISceneKey.self] } set { self[NativeUISceneKey.self] = newValue } }
    var nativeUIMessage: String { get { self[NativeUIMessageKey.self] } set { self[NativeUIMessageKey.self] = newValue } }
}

struct NativeUIView: View {
    let source: String
    @Environment(\.nativeUIScene) private var scene
    @Environment(\.nativeUIMessage) private var messageID
    @EnvironmentObject private var store: Store
    @State private var expanded = false
    @State private var preview: ImagePreviewItem?
    @State private var expandedPreview: ImagePreviewItem?
    @State private var error: String?
    @State private var generation = 0
    private var scope: String {
        SHA256.hash(data: Data("\(store.connection?.endpoint ?? "")|\(scene)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private var payload: [String: Any] {
        let messages: [[String: Any]] = store.displayMessages.filter {
            $0.role != "user" && ($0.sceneID ?? "sbs") == scene &&
                $0.text.range(of: "intelligent-ui", options: .caseInsensitive) != nil
        }.map { message in
            ["id": message.id.uuidString, "identity": message.sequence.map(String.init) ?? message.id.uuidString,
             "scope": scope, "text": message.text, "streaming": message.streaming == true]
        }
        return ["source": source, "messages": messages, "messageID": messageID,
                "storageKey": scope + "|" + messageID, "scope": scope,
                "saved": IntelligentUIStateCache.load(scope: scope)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("智能界面", systemImage: "slider.horizontal.3").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { expanded = true } label: { Label("展开", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .font(.caption).frame(minHeight: 44).accessibilityLabel("展开智能界面")
            }.padding(.horizontal, 10).background(ClientTheme.surface)
            if expanded {
                // Keep the bubble's layout without a second active renderer
                // behind the full-screen interface.
                Color.clear.frame(height: 440).accessibilityHidden(true)
            } else {
                IntelligentUIWebView(payload: payload, scope: scope, receive: receive).id(generation)
                    .frame(height: 440).accessibilityIdentifier("intelligentUI")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary).padding(8) }
        }.frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
            .fullScreenCover(isPresented: $expanded, onDismiss: { generation += 1 }) {
                NavigationStack {
                    IntelligentUIWebView(payload: payload, scope: scope, receive: receive)
                        .accessibilityIdentifier("expandedIntelligentUI")
                        .navigationTitle("智能界面").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { expanded = false } } }
                }.fullScreenCover(item: $expandedPreview) { ImagePreview(item: $0) }
            }
            .fullScreenCover(item: $preview) { ImagePreview(item: $0) }
    }
    private func receive(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "expand": expanded = true
        case "copy": if let text = event["text"] as? String, text.utf8.count <= 100000 { UIPasteboard.general.string = text }
        case "draft":
            guard let text = event["text"] as? String, text.utf8.count <= 100000 else { return }
            let snapshot = event["snapshot"] as? String ?? ""
            guard snapshot.utf8.count <= 100000 else { error = "当前界面内容过大，未放入草稿。"; return }
            guard (store.selected ?? "sbs") == scene else { error = "请先切换到这条消息所属的对话，再继续。"; return }
            store.intelligentUISelection = snapshot.isEmpty ? nil : snapshot
            store.intelligentUI = true
            // SurfaceArtifact may invoke edit immediately before continue. Replace
            // only the default edit draft, never an existing user-written draft.
            if store.draft == "请根据当前界面和我的选择继续修改。" { store.draft = text }
            else if !store.draft.hasSuffix(text) { store.draft += (store.draft.isEmpty ? "" : "\n\n") + text }
            expanded = false
        case "image":
            guard let src = event["src"] as? String else { return }
            Task {
                do {
                    let url: URL
                    if src.hasPrefix("data:image/"), src.utf8.count <= 28_000_000,
                       let comma = src.firstIndex(of: ","), src[..<comma].hasSuffix(";base64"),
                       let bytes = Data(base64Encoded: String(src[src.index(after: comma)...])), bytes.count <= 20 * 1024 * 1024,
                       let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                       let type = CGImageSourceGetType(source) as String?,
                       ["public.png", "public.jpeg", "org.webmproject.webp"].contains(type) {
                        url = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + "." + (UTType(type)?.preferredFilenameExtension ?? "png"))
                        try bytes.write(to: url, options: .atomic)
                    } else {
                        guard let remote = URL(string: src), remote.scheme == "https", remote.host != nil,
                              remote.user == nil, remote.password == nil else { return }
                        url = try await MarkdownImageLoader.load(remote).url
                    }
                    let item = ImagePreviewItem(url: url, title: event["title"] as? String ?? "图片")
                    if expanded { expandedPreview = item } else { preview = item }
                } catch { self.error = "图片读取失败，请重试。" }
            }
        case "error": error = event["text"] as? String
        default: break
        }
    }
}

private struct IntelligentUIWebView: UIViewRepresentable {
    let payload: [String: Any]
    let scope: String
    let receive: ([String: Any]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "townUI")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        if let url = Bundle.main.url(forResource: "iui", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { receive(["type": "error", "text": "智能界面资源缺失，请更新应用。"]) }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.parent = self; context.coordinator.render() }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName: "townUI")
        view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: IntelligentUIWebView
        weak var webView: WKWebView?
        var ready = false
        var lastPayload: Data?
        init(_ parent: IntelligentUIWebView) { self.parent = parent }
        func render() {
            guard ready, let view = webView,
                  let bytes = try? JSONSerialization.data(withJSONObject: parent.payload, options: .sortedKeys),
                  bytes.count <= 8_000_000, bytes != lastPayload else { return }
            lastPayload = bytes
            view.callAsyncJavaScript("window.renderTownUI(payload)", arguments: ["payload": parent.payload], in: nil, in: .page) { [weak self] result in
                if case .failure = result { self?.parent.receive(["type": "error", "text": "智能界面加载失败，请重新打开。负载内容已保留。"]) }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.webView === webView,
                  message.frameInfo.request.url?.isFileURL == true,
                  let event = message.body as? [String: Any] else { return }
            if event["type"] as? String == "ready" { ready = true; render(); return }
            if event["type"] as? String == "save", let key = event["key"] as? String, key.count <= 1000,
               let values = event["values"] as? [String: Any], values.count <= 50,
               let bytes = try? JSONSerialization.data(withJSONObject: values), bytes.count <= 100000 {
                IntelligentUIStateCache.save(values, key: key, scope: parent.scope); return
            }
            parent.receive(event)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler(url?.isFileURL == true && ["iui.html", "iui-runtime.html"].contains(url?.lastPathComponent ?? "") ? .allow : .cancel)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false; lastPayload = nil; webView.reload()
        }
    }
}

enum IntelligentUIStateCache {
    static func load(scope: String, defaults: UserDefaults = .standard) -> [String: Any] {
        let key = "intelligent-ui." + scope
        if let data = defaults.data(forKey: key),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return saved }
        return defaults.dictionary(forKey: key) ?? [:]
    }
    static func save(_ values: [String: Any], key: String, scope: String, defaults: UserDefaults = .standard) {
        var saved = load(scope: scope, defaults: defaults)
        guard saved[key] != nil || saved.count < 200 else { return }
        saved[key] = values
        // Protocol values include null, which is not a property-list value.
        guard let data = try? JSONSerialization.data(withJSONObject: saved), data.count <= 2_000_000 else { return }
        defaults.set(data, forKey: "intelligent-ui." + scope)
    }
}

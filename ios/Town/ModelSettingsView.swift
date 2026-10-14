import SwiftUI
struct ModelChoice: Identifiable { let id: String; let name: String }
struct ModelSettingsView: View {
    @Environment(Store.self) private var store
    @State private var routes: [ModelChoice] = []
    @State private var models: [ModelChoice] = []
    @State private var provider = ""
    @State private var model = ""
    @State private var thinking = "medium"
    @State private var apiKey = ""
    @State private var loading = false
    @State private var saving = false
    @State private var result: String?
    var body: some View {
        Form {
            if store.connection == nil { ContentUnavailableView("请先连接 Being 对话。", systemImage: "link", description: Text("选择当前 Being 使用的模型")) }
            else {
                Section("模型") {
                    if routes.isEmpty { TextField("服务商 / 线路 ID", text: $provider).textInputAutocapitalization(.never) }
                    else { Picker("线路", selection: $provider) { Text("选择线路").tag(""); ForEach(routes) { Text($0.name).tag($0.id) } } }
                    if !models.isEmpty { Picker("模型目录", selection: $model) { Text("自定义模型").tag(model); ForEach(models.filter { $0.id != model }) { Text($0.name).tag($0.id) } } }
                    TextField("模型 ID", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("思考深度", selection: $thinking) { ForEach(["off", "low", "medium", "high"], id: \.self) { Text(["off":"关闭","low":"低","medium":"中","high":"高"][$0] ?? $0).tag($0) } }
                }
                Section { SecureField("输入 API 密钥", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled() } header: { Text("线路凭据") }
                Section {
                    Button(saving ? "正在保存…" : "保存配置") { Task { await save() } }.disabled(saving || loading || store.busy || provider.isEmpty || model.isEmpty)
                    Button("重新读取") { Task { await load() } }.disabled(saving || loading)
                    if loading { ProgressView() }
                    if let result { Text(result).font(.footnote).textSelection(.enabled) }
                }
            }
        }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle("模型设置").task { await load() }.task(id: provider) { await catalog() }
    }
    private func choices(_ value: Any?) -> [ModelChoice] { (value as? [[String: Any]] ?? []).compactMap { item in let id = field(item, "id"); return id.isEmpty ? nil : ModelChoice(id: id, name: field(item, "name").isEmpty ? id : field(item, "name")) } }
    private func load() async {
        guard let c = store.connection else { return }; loading = true; defer { loading = false }
        do { let config = try await store.json(c, "/api/llm/config"); provider = field(config, "provider"); model = field(config, "model"); thinking = field(config, "thinking").isEmpty ? "medium" : field(config, "thinking"); if let list = try? await store.json(c, "/api/llm/routes") { routes = choices(list["routes"]) }; result = nil }
        catch { result = "无法读取模型设置，请检查连接和 relay secret。" }
    }
    private func catalog() async {
        models = []; guard !provider.isEmpty, let c = store.connection else { return }
        var q = URLComponents(); q.queryItems = [URLQueryItem(name: "route", value: provider)]
        if let data = try? await store.json(c, "/api/llm/models?" + (q.percentEncodedQuery ?? "")), !Task.isCancelled { models = choices(data["models"]) }
    }
    private func save() async {
        guard let c = store.connection, !store.busy else { return }; saving = true; result = nil; defer { saving = false }
        do {
            var patch: [String: Any] = ["provider": provider, "model": model.trimmingCharacters(in: .whitespacesAndNewlines), "thinking": thinking]
            if !apiKey.isEmpty { patch["api_key"] = apiKey }
            let data = try await store.json(c, "/api/llm/config", method: "PATCH", body: patch)
            if data["needs_key"] as? Bool == true { result = "当前线路需要有效 API Key。"; return }
            guard data["ok"] as? Bool == true, data["rolled_back"] as? Bool != true else { result = "配置未生效，服务端保留了原配置。"; return }
            apiKey = ""; result = "已保存。后续回复将使用新的模型设置。"
            let confirmed = try await store.json(c, "/api/llm/config"); model = field(confirmed, "model"); provider = field(confirmed, "provider")
        } catch { result = "保存失败或未确认，请重新读取配置后核对。" }
    }
}

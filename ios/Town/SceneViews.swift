import SwiftUI
struct SceneEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let binding: Bool
    @State private var name = ""
    @State private var id = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if binding { TextField("场景 ID",text:$id).textInputAutocapitalization(.never).autocorrectionDisabled() }
                TextField("场景名称",text:$name)
                if let error { Text(error).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle(binding ? "绑定已有场景" : "新建场景")
                .toolbar { AdaptiveToolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button(binding ? "绑定并进入" : "创建并进入") {
                        do { try store.createScene(name,binding:binding ? id.trimmingCharacters(in:.whitespacesAndNewlines) : nil); dismiss() } catch { self.error = error.localizedDescription }
                    }.disabled(store.busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (binding && id.isEmpty)) }
                 } }
        }
    }
}
struct SceneDetails: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text(store.current?.title ?? "场景")
                LabeledContent("场景 ID", value:store.selected ?? "").textSelection(.enabled)
                LabeledContent("客户端",value:"being-ios/0.2")
                Button("复制场景 ID") { UIPasteboard.general.string = store.selected }
            }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle("当前场景")
                .toolbar { AdaptiveToolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } }
        }
    }
}

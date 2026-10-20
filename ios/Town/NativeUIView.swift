import SwiftUI
import CryptoKit
import Charts

private struct NativeUISceneKey: EnvironmentKey { static let defaultValue = "" }
extension EnvironmentValues { var nativeUIScene: String { get { self[NativeUISceneKey.self] } set { self[NativeUISceneKey.self] = newValue } } }
struct NativeUIView: View {
    @Environment(\.nativeUIScene) private var scene
    let source: String
    @EnvironmentObject private var store: Store
    @State private var values: [String: Any] = [:]
    @State private var document: NativeUI.Document?
    @State private var error: String?
    @State private var showSource = false
    private var key: String { "native-ui." + SHA256.hash(data: Data("\(store.connection?.endpoint ?? "")|\(scene)|\(source)".utf8)).map { String(format: "%02x", $0) }.joined() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let document, !showSource {
                Text(document.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(document.body.enumerated()), id: \.offset) { _, node in
                    nodeView(node).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("用当前选择继续") { continueDraft() }
                    .buttonStyle(.borderedProminent)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            Button(showSource ? "查看界面" : "查看源码") { showSource.toggle() }.font(.caption)
            if showSource || document == nil { ScrollView(.horizontal) { Text(source).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) } }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ClientTheme.secondary.opacity(0.16), lineWidth: 1))
            .foregroundStyle(ClientTheme.text)
            .task(id: key) { do { let decoded = try NativeUI.decode(source); document = decoded; values = decoded.state; if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { for (k,v) in saved where values[k] != nil || k.hasPrefix("check.") { values[k] = v } }; error = nil } catch { self.error = error.localizedDescription; document = nil } }
    }
    private func set(_ key: String, _ value: Any) { values[key] = value; if let data = try? JSONSerialization.data(withJSONObject: values) { UserDefaults.standard.set(data, forKey: self.key) } }
    private func evaluated(_ v: Any?) -> String { NativeUI.display(NativeUI.evaluate(v, values)) }
    private func continueDraft() {
        guard let document else { return }
        let snapshot: [String: Any] = ["title":document.title,"values":values,"document":["version":1,"title":document.title,"state":document.state,"body":document.body]]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: .sortedKeys), data.count <= 100000 else { error = "当前选择内容过大。"; return }
        store.draft += (store.draft.isEmpty ? "" : "\n\n") + "请根据当前选择继续：\n" + String(decoding: data, as: UTF8.self)
    }
    private func nodeView(_ node: [String: Any]) -> AnyView {
        if let when = node["when"], NativeUI.evaluate(when, values) as? Bool == false { return AnyView(EmptyView()) }
        let type = node["type"] as? String ?? "", label = node["label"] as? String ?? "", bind = node["bind"] as? String ?? "", id = node["id"] as? String ?? ""
        let children = node["children"] as? [[String: Any]] ?? []
        let lo = node["min"] as? Double ?? 0, hi = node["max"] as? Double ?? 100, step = node["step"] as? Double ?? 1
        let numeric = Binding<Double>(get: { min(hi,max(lo,(values[bind] as? NSNumber)?.doubleValue ?? lo)) }, set: { set(bind,$0) })
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            switch type {
            case "divider": Divider()
            case "toggle": Toggle(label, isOn: Binding(get: { values[bind] as? Bool ?? false }, set: { set(bind,$0) }))
            case "input": TextField(label, text: Binding(get: { values[bind] as? String ?? "" }, set: { set(bind,String($0.prefix(10000))) })).textFieldStyle(.roundedBorder)
            case "number", "stepper": Stepper("\(label) · \(evaluated(["state":bind]))", value: numeric, in: lo...hi, step: step)
            case "slider": Text("\(label) · \(evaluated(node["value"] ?? ["state":bind]))"); Slider(value: numeric, in: lo...hi, step: step)
            case "select", "segmented", "choice":
                let options = (node["options"] as? [String] ?? []).map { ["id":$0,"label":$0] } + (node["items"] as? [[String: String]] ?? [])
                Picker(label, selection: Binding(get: { values[bind] as? String ?? "" }, set: { set(bind,$0) })) { ForEach(Array(options.enumerated()), id: \.offset) { _, option in Text(option["label"] ?? "").tag(option["id"] ?? "") } }.pickerStyle(.menu)
            case "button": Button(label) {
                switch node["action"] as? String {
                case "reset": values = document?.state ?? [:]; if let data = try? JSONSerialization.data(withJSONObject: values) { UserDefaults.standard.set(data, forKey: key) }
                case "copy": UIPasteboard.general.string = evaluated(node["value"])
                case "set": let changes = (node["changes"] as? [String:Any] ?? [:]).mapValues { NativeUI.evaluate($0,values) }; for (k,v) in changes where values[k] != nil { set(k,v) }
                default: continueDraft()
                }
            }
            case "list", "checklist", "timeline":
                if !label.isEmpty { Text(label).font(.headline) }
                ForEach(Array((node["items"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { index, item in
                    let key = item["bind"] as? String ?? "check.\(id).\(item["id"] as? String ?? String(index))"
                    let title = item["label"] as? String ?? ""
                    if type == "checklist" || type == "timeline" && node["checkable"] as? Bool != false { Toggle(title, isOn: Binding(get: { values[key] as? Bool ?? false }, set: { set(key,$0) })) }
                    else { Text(title) }
                    if let detail = item["description"] as? String { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            case "chart", "breakdown":
                if !label.isEmpty { Text(label).font(.headline) }
                let rows = node["rows"] as? [[Any]] ?? []
                Chart(Array(rows.enumerated()), id: \.offset) { _, row in
                    if row.count >= 2, let number = NativeUI.evaluate(row[1],values) as? NSNumber {
                        if node["variant"] as? String == "line" { LineMark(x: .value("名称", evaluated(row[0])), y: .value("数值", number.doubleValue)) }
                        else { BarMark(x: .value("名称", evaluated(row[0])), y: .value("数值", number.doubleValue)) }
                    }
                }.frame(height: 200).accessibilityLabel(label)
            case "table", "facts":
                if !label.isEmpty { Text(label).font(.headline) }
                ScrollView(.horizontal) { VStack(alignment: .leading) {
                    if let columns = node["columns"] as? [String] { HStack { ForEach(Array(columns.enumerated()), id: \.offset) { _, column in Text(column).bold().frame(width: 130, alignment: .leading) } } }
                    ForEach(Array((node["rows"] as? [[Any]] ?? []).enumerated()), id: \.offset) { _, row in HStack { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in Text(evaluated(cell)).frame(width: 130, alignment: .leading) } } }
                } }.font(.subheadline)
            case "progress": Text(label); ProgressView(value: min(1,max(0,((NativeUI.evaluate(node["value"],values) as? NSNumber)?.doubleValue ?? 0) - lo) / max(1,hi-lo)))
            default:
                if !label.isEmpty { Text(label).font(["heading","hero","section","card"].contains(type) ? .headline : .subheadline) }
                if node["value"] != nil { Text(evaluated(node["value"])).font(type == "metric" ? .title2 : .body).textSelection(.enabled) }
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in nodeView(child) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading))
    }
}

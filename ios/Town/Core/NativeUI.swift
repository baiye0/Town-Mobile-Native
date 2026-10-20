import Foundation

/// A bounded, data-only subset of the desktop protocol. No generated code executes.
enum NativeUI {
    static let types: Set<String> = ["stack","row","grid","box","split","section","card","hero","callout","heading","text","metric","badge","divider","input","number","slider","stepper","toggle","select","segmented","choice","button","table","facts","chart","breakdown","list","checklist","timeline","progress"]
    static let context = "\n\n[客户端 Intelligent UI Beta 上下文]\n用户已开启智能 UI。本条可用 intelligent-ui 代码围栏输出 JSON v1：{\"version\":1,\"title\":\"标题\",\"state\":{\"count\":2},\"body\":[{\"id\":\"countInput\",\"type\":\"stepper\",\"label\":\"数量\",\"bind\":\"count\",\"min\":1,\"max\":20}]}。支持组件：stack,row,grid,box,split,section,card,hero,callout,heading,text,metric,badge,divider,input,number,slider,stepper,toggle,select,segmented,choice,button,table,facts,chart,breakdown,list,checklist,timeline,progress。value 可为标量、{state:状态名}、{op:add/mul/sub/div/min/max/round/concat/eq/lt/gt/if/not/and/or/fixed/pow,args:[表达式]}。select/segmented 使用 options 字符串数组，choice/list/checklist/timeline 使用 items:[{id,label,description?,bind?}]；table/chart/facts 用 columns 和 rows。button.action 支持 reset/copy/continue/set；set 使用 changes；continue 将选择放入草稿，由用户发送。仅使用已声明的 bind；每个节点有唯一 id。布局按窄屏纵向适配。不支持 app、diagram、tabs、图片或跨轮 patch；需要修改时输出独立的新完整界面。普通 Markdown 仍可用于说明。\n[/客户端 Intelligent UI Beta 上下文]"
    struct Document { var title: String; var state: [String: Any]; var body: [[String: Any]] }
    static func decode(_ source: String) throws -> Document {
        guard source.utf8.count <= 200000 else { throw PortalError.server("交互界面过大") }
        var raw: [String: Any]
        if let data = source.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["version"] as? Int == 1 { raw = object }
        else {
            var title = "", state: [String: Any] = [:], nodes: [String: [String: Any]] = [:], parents: [String: String] = [:], order: [String] = [], begun = false, committed = false, lastSeq = -1
            for line in source.split(separator: "\n") {
                guard let data = String(line).data(using: .utf8), let record = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PortalError.invalidResponse }
                if let seq = record["seq"] as? Int { if seq <= lastSeq { continue }; lastSeq = seq }
                guard !committed else { throw PortalError.invalidResponse }
                switch record["op"] as? String {
                case "begin": guard !begun, record["version"] as? Int == 2, record["mode"] as? String != "patch", record["baseRevision"] == nil else { throw PortalError.server("此界面需要桌面端的跨轮更新能力") }; title = record["title"] as? String ?? ""; begun = true
                case "state": guard begun, let key = record["key"] as? String else { throw PortalError.invalidResponse }; state[key] = record["initial"] ?? NSNull()
                case "node": guard begun, let node = record["node"] as? [String: Any], let id = node["id"] as? String, nodes.count < 200 else { throw PortalError.invalidResponse }; if nodes[id] == nil { order.append(id) }; nodes[id] = node; parents[id] = record["parent"] as? String
                case "commit": guard begun else { throw PortalError.invalidResponse }; committed = true
                default: throw PortalError.invalidResponse
                }
            }
            guard begun && committed else { throw PortalError.server("交互界面尚未生成完成") }
            for parent in parents.values where nodes[parent] == nil { throw PortalError.invalidResponse }
            var visiting = Set<String>(), visited = Set<String>()
            func build(_ id: String, _ depth: Int) throws -> [String: Any] {
                guard depth <= 12, visiting.insert(id).inserted, var node = nodes[id] else { throw PortalError.invalidResponse }
                var children = node["children"] as? [[String: Any]] ?? []
                for child in order where parents[child] == id { children.append(try build(child, depth + 1)) }
                if !children.isEmpty { node["children"] = children }; visiting.remove(id); visited.insert(id); return node
            }
            let body = try order.filter { parents[$0] == nil }.map { try build($0, 0) }
            guard visited.count == nodes.count else { throw PortalError.invalidResponse }
            raw = ["title":title,"state":state,"body":body]
        }
        guard let title = raw["title"] as? String, title.count <= 200, let state = raw["state"] as? [String: Any], state.count <= 50, let body = raw["body"] as? [[String: Any]], state.values.allSatisfy({ $0 is String || $0 is NSNumber || $0 is NSNull }) else { throw PortalError.invalidResponse }
        var ids = Set<String>()
        func validate(_ nodes: [[String: Any]], _ depth: Int) throws {
            guard depth <= 12 else { throw PortalError.invalidResponse }
            for node in nodes {
                guard let id = node["id"] as? String, DeliveryRules.safeID(id), ids.insert(id).inserted, ids.count <= 200, let type = node["type"] as? String, types.contains(type) else { throw PortalError.server("包含移动端尚不支持的交互组件，已保留源码") }
                if let bind = node["bind"] as? String, state[bind] == nil { throw PortalError.invalidResponse }
                if ["slider","stepper","number"].contains(type) { let lo = node["min"] as? Double ?? 0, hi = node["max"] as? Double ?? 100, step = node["step"] as? Double ?? 1; guard lo.isFinite, hi.isFinite, hi > lo, step.isFinite, step > 0 else { throw PortalError.invalidResponse } }
                if let rows = node["rows"] as? [[Any]], rows.count > 500 { throw PortalError.invalidResponse }
                if let items = node["items"] as? [[String: Any]], items.count > 200 { throw PortalError.invalidResponse }
                try validate(node["children"] as? [[String: Any]] ?? [], depth + 1)
            }
        }
        try validate(body, 0); return Document(title: title, state: state, body: body)
    }
    static func evaluate(_ expression: Any?, _ state: [String: Any], depth: Int = 0) -> Any {
        guard depth < 20 else { return "表达式过深" }
        guard let e = expression as? [String: Any] else { return expression ?? "" }
        if let key = e["state"] as? String { return state[key] ?? "" }
        let args = e["args"] as? [Any] ?? []; guard args.count <= 20 else { return "表达式过长" }
        let values = args.map { evaluate($0, state, depth: depth + 1) }, n = values.map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        func value(_ i: Int) -> Any { values.indices.contains(i) ? values[i] : "" }
        func number(_ i: Int) -> Double { n.indices.contains(i) ? n[i] : 0 }
        let result: Any
        switch e["op"] as? String {
        case "add": result = n.reduce(0,+)
        case "mul": result = n.reduce(1,*)
        case "sub": result = number(0) - number(1)
        case "div": result = number(1) == 0 ? 0 : number(0) / number(1)
        case "pow": result = pow(number(0), number(1))
        case "min": result = n.min() ?? 0
        case "max": result = n.max() ?? 0
        case "round": result = number(0).rounded()
        case "fixed": result = String(format: "%.*f", min(10,max(0,Int(number(1).clamped(to: 0...10)))), number(0))
        case "concat": result = values.map(display).joined()
        case "eq": result = display(value(0)) == display(value(1))
        case "lt": result = number(0) < number(1)
        case "gt": result = number(0) > number(1)
        case "not": result = !(value(0) as? Bool ?? false)
        case "and": result = values.allSatisfy { $0 as? Bool == true }
        case "or": result = values.contains { $0 as? Bool == true }
        case "if": result = value(0) as? Bool == true ? value(1) : value(2)
        default: result = "不支持的表达式"
        }
        if let number = result as? Double, !number.isFinite { return "数值超出范围" }; return result
    }
    static func display(_ value: Any) -> String { value is NSNull ? "" : String(describing: value) }
}
private extension Double { func clamped(to range: ClosedRange<Double>) -> Double { isFinite ? min(range.upperBound, max(range.lowerBound, self)) : 0 } }

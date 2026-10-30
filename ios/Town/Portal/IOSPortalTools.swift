import Foundation
import UIKit

extension IOSPortalStore {
    var tools: [[String: Any]] {
        func string(_ description: String = "") -> [String: Any] { ["type": "string", "description": description] }
        func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
            ["name": name, "description": description, "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false]]
        }
        var result = [
            tool("portal_status", "iOS Portal version, connection and actual supported capabilities."),
            tool("portal_ios_capabilities", "Current Being grants and independent iOS system permission status. Permissions must be enabled on the phone."),
            tool("portal_ios_actions", "Poll a native write by request_id. Writes execute immediately; unknown means the system result needs checking before retrying.", ["request_id": string()], required: ["request_id"]),
            tool("portal_ios_activity", "Recent tool execution status; contains no arguments or personal data.")
        ]
        if options.files {
            result += [
                tool("portal_file_list", "List up to 500 entries within this Being's workspace.", ["path": string()]),
                tool("portal_file_read", "Read UTF-8 text in the workspace, maximum 10 MB file; response limited to 160000 characters. offset and limit are zero-based line offset and line count.", ["path": string(), "offset": ["type": "integer", "minimum": 0], "limit": ["type": "integer", "minimum": 1]], required: ["path"]),
                tool("portal_file_write", "Write or append UTF-8/base64 content within the workspace, at most 10 MB. Does not access other app files.", ["path": string(), "content": string(), "append": ["type": "boolean"], "encoding": ["type": "string", "enum": ["utf8", "base64"]]], required: ["path", "content"]),
                tool("portal_file_edit", "Replace a unique literal old_text with new_text in a UTF-8 workspace file. Multiple matches are rejected.", ["path": string(), "old_text": string(), "new_text": string()], required: ["path", "old_text", "new_text"]),
                tool("portal_search", "Case-insensitive LITERAL text search (not regex). Bounded scan: 2000 entries / 20 MB, at most 200 matches. Results may be incomplete.", ["pattern": string(), "path": string(), "max_matches": ["type": "integer", "minimum": 1, "maximum": 200]], required: ["pattern"])
            ]
        }
        for capability in ["calendar", "reminders", "contacts", "location"] {
            let read = options.grants.contains(capability + ".read"), write = options.grants.contains(capability + ".write")
            guard read || write else { continue }
            let actions = (read ? (capability == "location" ? ["get"] : ["list", "get"] + (["calendar", "reminders"].contains(capability) ? ["calendars"] : [])) : []) + (write ? ["create", "update", "delete"] : [])
            var properties: [String: Any] = ["action": ["type": "string", "enum": actions]]
            if capability != "location" {
                properties.merge(["id": string("System record identifier"), "query": string("Literal search text")]) { _, new in new }
                if write { properties["request_id"] = string("Optional idempotency key. Reuse the same ID and identical arguments when retrying an uncertain result.") }
                if capability == "contacts" {
                    if write { properties.merge(["given_name": string(), "family_name": string(), "phones": ["type": "array", "items": string(), "maxItems": 20], "emails": ["type": "array", "items": string(), "maxItems": 20]]) { _, new in new } }
                } else {
                    properties["calendar_id"] = string()
                    if write { properties["title"] = string(); properties["notes"] = string() }
                    if capability == "calendar" {
                        properties["start"] = string("ISO 8601 with timezone; required for list/create/update")
                        properties["end"] = string("ISO 8601 with timezone; required for list/create/update")
                        if write { properties["all_day"] = ["type": "boolean"] }
                    } else {
                        properties["completed"] = ["type": "boolean"]
                        if write { properties["due"] = string("ISO 8601 due time with timezone; also sets an alarm") }
                    }
                }
            }
            result.append(tool("portal_ios_" + capability,
                "iOS \(capability). Writes execute immediately when this Being and the system grant are available; portal_ios_actions can inspect a recorded result. System permission is also required. Lists return at most 200 items. Calendar/reminder recurring records cannot be modified; calendar invitations are not supported. Updates preserve omitted fields; contact phone/email arrays replace those fields.", properties, required: ["action"]))
        }
        let healthCategories = IOSPortalHealth.categories.map(\.id).filter { options.grants.contains("health." + $0 + ".read") }
        if !healthCategories.isEmpty, health.available {
            result.append(tool("portal_ios_health", "Read-only health records selected by the user for this Being. Use {\"category\":\"sleep\"} for the last 7 days. Optional start/end must be ISO 8601 with timezone; range at most 31 days, latest 200 samples; cumulative activity metrics use daily sums in UTC. iOS hides read authorization: empty results do not mean zero or denied. Sleep records can overlap; do not sum them blindly.", ["category": ["type": "string", "enum": healthCategories], "start": string("Optional ISO 8601 with timezone; defaults to 7 days before end"), "end": string("Optional ISO 8601 with timezone; defaults to now")], required: ["category"]))
        }
        return result
    }
    func dispatch(_ request: [String: Any]) async -> [String: Any]? {
        let id = request["id"] ?? NSNull()
        func error(_ code: Int, _ message: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]] }
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else { return error(-32600, "Invalid request") }
        // Notifications never execute tools or produce responses.
        guard request["id"] != nil else { return nil }
        var result: [String: Any]
        switch method {
        case "initialize": result = ["protocolVersion": "2024-11-05", "capabilities": ["tools": ["listChanged": true]], "serverInfo": ["name": options.name, "version": "0.2.0-ios"]]
        case "ping": result = [:]
        case "tools/list": result = ["tools": tools]
        case "tools/call":
            guard let params = request["params"] as? [String: Any], let name = params["name"] as? String,
                  let definition = tools.first(where: { $0["name"] as? String == name }) else { return error(-32602, "Unknown or disabled tool") }
            guard params["arguments"] == nil || params["arguments"] is [String: Any] else { return error(-32602, "Invalid arguments") }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let owner = connection, currentGeneration = generation
            let activityID = UUID()
            // Status/capability polling must not bury actual data reads.
            let logActivity = !["portal_status", "portal_ios_capabilities", "portal_ios_activity", "portal_ios_actions"].contains(name)
            if logActivity { record(name, "执行中", id: activityID) }
            do {
                try validateArguments(args, definition: definition)
                let value = try await call(name, args)
                try Task.checkCancellation()
                guard owner == connection, currentGeneration == generation else { return nil }
                let text = String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
                guard text.utf8.count <= 1024 * 1024 else { throw PortalError.server("结果过大，请缩小查询范围。") }
                result = ["content": [["type": "text", "text": text]], "isError": false]
                if logActivity {
                    let rows = value["records"] as? [[String: Any]]
                    let status = value["status"] as? String == "unknown" ? "结果待核实" : rows.map { $0.isEmpty ? "读取完成 · 无可用记录" : "读取完成 · \($0.count) 条" } ?? "已完成"
                    record(name, status, id: activityID)
                }
            } catch {
                guard owner == connection, currentGeneration == generation, !Task.isCancelled else { return nil }
                let message = error is PortalError ? error.localizedDescription : "操作失败，请检查权限、参数和本地文件。"
                result = ["content": [["type": "text", "text": message]], "isError": true]
                if logActivity { record(name, "失败", id: activityID) }
            }
        default: return error(-32601, "Method not found")
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }
    private func validateArguments(_ args: [String: Any], definition: [String: Any]) throws {
        let schema = definition["inputSchema"] as? [String: Any] ?? [:]
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        let required = schema["required"] as? [String] ?? []
        let missing = required.filter { args[$0] == nil }
        let unknown = Set(args.keys).subtracting(properties.keys).sorted()
        if !missing.isEmpty || !unknown.isEmpty {
            var details = [String]()
            if !missing.isEmpty { details.append("缺少必填字段：" + missing.joined(separator: ", ")) }
            if !unknown.isEmpty { details.append("不支持的字段：" + unknown.prefix(20).map { String($0.prefix(80)) }.joined(separator: ", ")) }
            details.append("允许字段：" + properties.keys.sorted().joined(separator: ", "))
            if definition["name"] as? String == "portal_ios_health" {
                let categories = properties["category"]?["enum"] as? [String] ?? []
                let example = categories.contains("sleep") ? "sleep" : (categories.first ?? "steps")
                details.append("示例：{\"category\":\"\(example)\"}，默认最近 7 天；可选 start/end 为含时区的 ISO 8601 时间，范围不超过 31 天。category 可选：" + categories.joined(separator: ", "))
            }
            throw PortalError.server(details.joined(separator: "；"))
        }
        for (key, value) in args {
            if let text = value as? String {
                let limit = ["query": 256, "given_name": 256, "family_name": 256, "title": 500, "path": 2048, "id": 4096, "calendar_id": 4096, "request_id": 128, "notes": 10000][key] ?? 1024 * 1024
                guard text.utf8.count <= limit else { throw PortalError.server("参数 \(key) 过长。") }
            }
            let spec = properties[key]!
            let type = spec["type"] as? String
            let number = value as? NSNumber
            let isBool = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            let valid = (type == "string" && value is String) || (type == "boolean" && isBool) || (type == "array" && value is [String]) || (type == "integer" && number != nil && !isBool && number!.doubleValue.isFinite && number!.doubleValue.rounded() == number!.doubleValue && abs(number!.doubleValue) < 1_000_000_000)
            guard valid else { throw PortalError.server("参数 \(key) 类型不正确，应为 \(type ?? "schema 指定类型")。") }
            if let choices = spec["enum"] as? [String], !choices.contains(value as? String ?? "") { throw PortalError.server("参数 \(key) 不支持此值，可选：\(choices.joined(separator: ", "))。") }
            if let min = spec["minimum"] as? Int, (number?.intValue ?? 0) < min { throw PortalError.server("参数 \(key) 小于最小值。") }
            if let max = spec["maximum"] as? Int, (number?.intValue ?? 0) > max { throw PortalError.server("参数 \(key) 超过最大值。") }
        }
    }
    func call(_ name: String, _ args: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "portal_status": return ["version": "0.2.0-ios", "platform": "ios", "name": options.name, "connection": phase, "background": "foreground_only", "tools": tools.compactMap { $0["name"] as? String }, "unsupported": ["exec", "process", "web_fetch", "screenshot", "notification_access", "geofences", "kits", "subagent"]]
        case "portal_ios_capabilities":
            return ["grants": options.grants.sorted(), "system_access": Dictionary(uniqueKeysWithValues: ["calendar", "reminders", "contacts", "location"].map { ($0, permissions.permission($0).label) }), "health": ["available": health.available, "linked": healthLinked, "read_authorization": "not_disclosed", "write_access": false, "categories": IOSPortalHealth.categories.filter { options.grants.contains("health." + $0.id + ".read") }.map { ["category": $0.id, "name": $0.title, "unit": $0.unitName ?? "", "aggregation": IOSPortalHealth.dailyTotals.contains($0.id) ? "daily_sum" : "samples"] }, "query_example": ["category": options.grants.contains("health.sleep.read") ? "sleep" : (IOSPortalHealth.categories.first { options.grants.contains("health." + $0.id + ".read") }?.id ?? "sleep")], "default_days": 7, "max_days": 31, "input_schema": tools.first { $0["name"] as? String == "portal_ios_health" }?["inputSchema"] ?? NSNull()], "writes": "immediate_with_being_and_system_grants", "background": "foreground_only"]
        case "portal_ios_actions":
            let id = try LocalPortalRules.string(args, "request_id", max: 128)
            guard let item = actions.first(where: { $0.id == id }) else { throw PortalError.server("未找到请求记录。") }; return actionResult(item)
        case "portal_ios_activity": return ["activity": activity.map { ["time": $0.time.ISO8601Format(), "tool": $0.tool, "status": $0.status] }]
        default: break
        }
        if name.hasPrefix("portal_file_") || name == "portal_search" {
            guard options.files, let workspace else { throw PortalError.server("文件能力未开启或工作区不可用。") }
            try Task.checkCancellation()
            if ["portal_file_list", "portal_file_read", "portal_search"].contains(name) {
                // Reads/search can scan megabytes. Keep them off the UI actor,
                // and discard results if access or the connection changed.
                let owner = connection, session = generation, permission = fileGeneration
                let input = try JSONSerialization.data(withJSONObject: args)
                let operation = Task.detached(priority: .utility) {
                    try Task.checkCancellation()
                    let arguments = try JSONSerialization.jsonObject(with: input) as? [String: Any] ?? [:]
                    let result = try Self.fileCall(name, arguments, workspace: workspace)
                    return try JSONSerialization.data(withJSONObject: result)
                }
                let output = try await withTaskCancellationHandler {
                    try await operation.value
                } onCancel: { operation.cancel() }
                try Task.checkCancellation()
                guard owner == connection, session == generation, permission == fileGeneration,
                      options.files, self.workspace != nil else { throw PortalError.server("文件访问已撤销。") }
                return try JSONSerialization.jsonObject(with: output) as? [String: Any] ?? [:]
            }
            // Mutations remain serialized with stop/revocation and local imports.
            return try Self.fileCall(name, args, workspace: workspace)
        }
        if name == "portal_ios_health" {
            let category = try LocalPortalRules.string(args, "category")
            let key = "health." + category + ".read"
            guard workspace != nil, options.grants.contains(key) else { throw PortalError.server("当前 Being 未获此类健康数据访问许可。") }
            let owner = connection, session = generation, permission = healthGeneration
            let result: [String: Any]
            do { result = try await health.read(args) }
            catch let error as PortalError { throw PortalError.server("健康查询 \(category)：" + error.localizedDescription) }
            try Task.checkCancellation()
            guard owner == connection, session == generation, permission == healthGeneration, workspace != nil, options.grants.contains(key) else { throw PortalError.server("健康数据访问已撤销。") }
            return result
        }
        let write = ["create", "update", "delete"].contains(args["action"] as? String ?? "")
        try check(name, write: write)
        if write { return try enqueue(name, args: args) }
        let result = try await native.read(capability(name), args)
        try check(name) // A permission may be revoked while awaiting a system callback.
        return result
    }
    nonisolated static func fileCall(_ name: String, _ args: [String: Any], workspace: LocalPortalWorkspace) throws -> [String: Any] {
        let path = args["path"] as? String ?? "."
        switch name {
        case "portal_file_list": return ["entries": try workspace.list(path), "limit": 500]
        case "portal_search": return ["matches": try workspace.search(LocalPortalRules.string(args, "pattern"), path: path, limit: args["max_matches"] as? Int ?? 100), "bounded_scan": true]
        case "portal_file_read":
            guard let text = String(data: try workspace.read(path), encoding: .utf8) else { throw PortalError.server("该文件不是 UTF-8 文本，可在手机工作区导出。") }
            let lines = text.components(separatedBy: "\n"), offset = max(0, args["offset"] as? Int ?? 0)
            let selected = lines.dropFirst(min(offset, lines.count)).prefix(max(1, min(args["limit"] as? Int ?? 2000, 10000))).joined(separator: "\n")
            return ["text": String(selected.prefix(160000)), "total_lines": lines.count, "offset": offset, "truncated": selected.count > 160000 || offset + min(args["limit"] as? Int ?? 2000, 10000) < lines.count]
        case "portal_file_write":
            let content = args["content"] as? String ?? ""
            let data: Data
            if args["encoding"] as? String == "base64" {
                guard let decoded = Data(base64Encoded: content) else { throw PortalError.server("base64 内容无效。") }; data = decoded
            } else { data = Data(content.utf8) }
            let output = args["append"] as? Bool == true ? (try workspace.read(path)) + data : data
            try workspace.write(path, data: output); return ["written": output.count, "path": path]
        case "portal_file_edit":
            let old = try LocalPortalRules.string(args, "old_text", max: LocalPortalRules.maxFileSize)
            let new = args["new_text"] as? String ?? ""
            guard let text = String(data: try workspace.read(path), encoding: .utf8) else { throw PortalError.server("该文件不是 UTF-8 文本。") }
            let pieces = text.components(separatedBy: old)
            guard pieces.count == 2 else { throw PortalError.server("old_text 必须在文件中唯一匹配。") }
            try workspace.write(path, data: Data(pieces.joined(separator: new).utf8)); return ["replacements": 1, "path": path]
        default: throw PortalError.server("未知文件工具。")
        }
    }
}

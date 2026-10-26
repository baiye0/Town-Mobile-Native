import Foundation
import CoreFoundation

struct GenerationJob: Equatable {
    let index: Int; let title: String; let submission: String; let id: String?; let request: String; let error: String?
}
struct GenerationReceipt { let being: String; let jobs: [GenerationJob] }
struct GenerationPart { let text: String; var receipt = false }
struct GenerationImage: Equatable { let url: String; let label: String }
struct GenerationSnapshot {
    let id: String; let status: String; let deadline: Double; let delay: Double; let action: Bool; let images: [GenerationImage]; let availability: String
    func wait(_ now: Double) -> Double? {
        guard ["queued", "running"].contains(status), !action, deadline > now else { return nil }
        return min(max(1000, min(60000, delay)), deadline - now)
    }
    func notice(_ now: Double) -> String {
        if action || status == "uncertain" || (["queued", "running"].contains(status) && deadline <= now) { return "结果待核对，可重新查询" }
        if availability == "expired" { return "图片已失效，可重新查询" }
        return ["queued": "排队中", "running": "正在生成", "succeeded": "生成成功", "failed": "生成失败", "cancelled": "已取消"][status] ?? "结果待核对"
    }
}
enum ImageGeneration {
    private static func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: "^(?:" + pattern + ")$", options: .regularExpression) != nil }
    private static func exact(_ o: [String: Any], _ keys: [String]) -> Bool { Set(o.keys) == Set(keys) }
    private static func nullable(_ o: [String: Any], _ key: String) -> Bool { o[key] is NSNull || (o[key] as? String).map { $0.count <= 256 } == true }
    private static func integer(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, abs(n.doubleValue) <= 9007199254740991, n.doubleValue.rounded() == n.doubleValue else { return nil }; return n.doubleValue
    }
    static func parse(_ text: String) -> GenerationReceipt? {
        guard text.utf8.count <= 65536, let data = text.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              exact(o, ["type", "version", "being_id", "jobs"]), o["type"] as? String == "being.image-generation", integer(o["version"]) == 1,
              let being = o["being_id"] as? String, matches(being, "[A-Za-z0-9_-]{1,128}"), let rows = o["jobs"] as? [[String: Any]], (1...24).contains(rows.count) else { return nil }
        var jobs: [GenerationJob] = [], keys = Set<String>(), ids = Set<String>()
        for (i, j) in rows.enumerated() {
            guard exact(j, ["index", "title", "submission", "generation_id", "client_request_id", "error_code"]), integer(j["index"]) == Double(i + 1),
                  let title = j["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
                  let submission = j["submission"] as? String, ["accepted", "rejected", "unknown"].contains(submission),
                  let request = j["client_request_id"] as? String, matches(request, "[A-Za-z0-9_-]{1,128}"), keys.insert(request).inserted,
                  nullable(j, "generation_id"), nullable(j, "error_code") else { return nil }
            let id = j["generation_id"] as? String
            if let id, !matches(id, "gen_[A-Za-z0-9_-]{1,124}") || !ids.insert(id).inserted { return nil }
            guard submission != "accepted" || id != nil, submission != "rejected" || id == nil else { return nil }
            jobs.append(GenerationJob(index: i + 1, title: title, submission: submission, id: id, request: request, error: j["error_code"] as? String))
        }
        return GenerationReceipt(being: being, jobs: jobs)
    }
    static func parts(_ text: String) -> [GenerationPart] {
        guard text.contains("being.image-generation") else { return [GenerationPart(text: text)] }
        let source = text as NSString; var cursor = 0, plain = 0; var result: [GenerationPart] = []
        func nextLine(_ start: Int) -> Int { let r = source.range(of: "\n", range: NSRange(location: start, length: source.length - start)); return r.location == NSNotFound ? source.length : r.location + 1 }
        func emit(_ start: Int, _ end: Int, _ value: String) {
            let object = value.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
            let candidate: Bool
            if let object { candidate = (object as? [String: Any])?["type"] as? String == "being.image-generation" }
            else { candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") && value.range(of: #""type"\s*:\s*"being\.image-generation""#, options: .regularExpression) != nil }
            if candidate {
                if start > plain { result.append(GenerationPart(text: source.substring(with: NSRange(location: plain, length: start - plain)))) }
                result.append(GenerationPart(text: value, receipt: true)); plain = end
            }
        }
        let fence = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})\s*(.*)$"#)
        while cursor < source.length {
            let next = nextLine(cursor), line = source.substring(with: NSRange(location: cursor, length: next - cursor)).trimmingCharacters(in: .newlines) as NSString
            if let m = fence.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) {
                let mark = line.substring(with: m.range(at: 1)), language = line.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces).lowercased()
                var close = next, end = source.length
                while close < source.length {
                    let after = nextLine(close), candidate = source.substring(with: NSRange(location: close, length: after - close)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if candidate.count >= mark.count && candidate.allSatisfy({ $0 == mark.first! }) { end = after; break }; close = after
                }
                if ["", "json", "being-image-generation"].contains(language) { emit(cursor, end, source.substring(with: NSRange(location: next, length: close - next))) }
                cursor = end; continue
            }
            let range = line.range(of: #"^ {0,3}(\{|\[(?=$|\s|\{|\[|"|\d|\]|-|true\b|false\b|null\b))"#, options: .regularExpression)
            if range.location != NSNotFound {
                let start = cursor + range.length - 1; var end = start, depth = 0; var quoted = false, escaped = false
                while end < source.length {
                    let c = source.character(at: end); end += 1
                    if quoted { if escaped { escaped = false } else if c == 92 { escaped = true } else if c == 34 { quoted = false } }
                    else if c == 34 { quoted = true } else if c == 123 || c == 91 { depth += 1 } else if c == 125 || c == 93 { depth -= 1; if depth == 0 { break } }
                }
                if source.character(at: start) == 123 { emit(cursor, end, source.substring(with: NSRange(location: start, length: end - start))) }
                cursor = end; continue
            }
            cursor = next
        }
        if plain < source.length { result.append(GenerationPart(text: source.substring(from: plain))) }; return result
    }
    static func snapshot(_ o: [String: Any], job: GenerationJob) throws -> GenerationSnapshot {
        guard let id = o["id"] as? String, matches(id, "gen_[A-Za-z0-9_-]{1,124}"), job.id == nil || job.id == id, o["client_request_id"] as? String == job.request,
              let status = o["status"] as? String, ["queued", "running", "uncertain", "succeeded", "failed", "cancelled"].contains(status),
              let stage = o["stage"] as? String, stage.count <= 128, let deadline = integer(o["deadline"]), deadline > 0,
              let delay = integer(o["poll_after_ms"]), delay >= 0, nullable(o, "required_action"), nullable(o, "error_code"),
              o["required_action"] is NSNull || o["required_action"] as? String == "operator_reconciliation_required",
              let availability = o["availability"] as? String, ["pending", "available", "expired"].contains(availability) else { throw PortalError.invalidResponse }
        var images: [GenerationImage] = []
        if status == "succeeded" && availability == "available" {
            guard let manifest = o["manifest"] as? [String: Any], integer(manifest["version"]) == 1, manifest["kind"] as? String == "image", let outputs = manifest["outputs"] as? [[String: Any]], (1...16).contains(outputs.count) else { throw PortalError.invalidResponse }
            for out in outputs {
                guard let outputID = out["id"] as? String, outputID.count <= 256, let attachment = out["attachment"] as? [String: Any], attachment["source"] as? String == "being-service",
                      let aid = attachment["attachment_id"] as? String, matches(aid, "att_[A-Za-z0-9_-]{1,124}"), let mime = out["mime"] as? String, matches(mime, "image/(png|jpeg|webp|gif|avif)"),
                      let raw = out["view_url"] as? String, raw.count <= 16384, let url = URLComponents(string: raw), url.scheme == "https", url.host == "beings.town", url.port == nil || url.port == 443,
                      url.user == nil, url.password == nil, url.fragment == nil, url.percentEncodedPath == "/api/being-service/v1/assets/\(aid)/view", url.queryItems?.contains(where: { $0.name == "token" && !($0.value ?? "").isEmpty }) == true else { throw PortalError.invalidResponse }
                images.append(GenerationImage(url: raw, label: job.title))
            }
        }
        return GenerationSnapshot(id: id, status: status, deadline: deadline, delay: delay, action: !(o["required_action"] is NSNull), images: images, availability: availability)
    }
}

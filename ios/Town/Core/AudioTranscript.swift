import Foundation

public enum AudioTranscript {
    public static func display(_ text: String) -> String {
        let preamble = "[说话人编号仅在本录音内有效，由模型根据声音区分，不代表真实身份或已确认的销售/客户角色；unknown 表示无法可靠区分。]"
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix(preamble) { value = String(value.dropFirst(preamble.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        let regex = try! NSRegularExpression(pattern: "\\[说话人 ([A-Z])\\]")
        let speakers = Set(regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { Range($0.range(at: 1), in: value).map { String(value[$0]) } })
        if speakers.count == 1 && !value.contains("[说话人不确定]") {
            value = value.replacingOccurrences(of: "\\[说话人 [A-Z]\\]\\s*", with: "", options: .regularExpression)
        }
        return value
    }
}

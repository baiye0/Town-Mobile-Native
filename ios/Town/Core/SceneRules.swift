import Foundation
public enum SceneRules {
    public static func validID(_ value: String) -> Bool { value.range(of: "^[\\x21-\\x7e]{1,256}$", options: .regularExpression) != nil }
    public static func validName(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 128 && value.range(of: "[\\r\\n\\x00-\\x1f]", options: .regularExpression) == nil }
    public static func stripTransition(_ text: String) -> String { text.replacingOccurrences(of: "^【新消息来自 scene「[^」\\r\\n]{1,256}」】\\r?\\n\\r?\\n", with: "", options: .regularExpression) }
}

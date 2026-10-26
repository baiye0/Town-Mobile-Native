import Foundation

enum IOSPortalPermissionState {
    case notDetermined, allowed, limited, approximate, writeOnly, denied, restricted, unavailable
    var available: Bool { [.allowed, .limited, .approximate].contains(self) }
    var canRequest: Bool { self == .notDetermined || self == .writeOnly }
    var label: String {
        switch self {
        case .notDetermined: return "尚未请求"
        case .allowed: return "已允许"
        case .limited: return "仅所选联系人"
        case .approximate: return "已允许 · 大致位置"
        case .writeOnly: return "仅添加日程，尚未允许读取"
        case .denied: return "已拒绝，请在系统设置中修改"
        case .restricted: return "受系统限制"
        case .unavailable: return "不可用，请检查系统服务"
        }
    }
}

@MainActor protocol IOSPortalPermissions: AnyObject {
    func permission(_ capability: String) -> IOSPortalPermissionState
    func authorize(_ capability: String) async throws
}

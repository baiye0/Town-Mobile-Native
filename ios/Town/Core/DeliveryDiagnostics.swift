import Foundation

struct AttachmentHTTPError: Error, LocalizedError {
    let status: Int
    var code: String? = nil
    var errorDescription: String? {
        DeliveryDiagnostics.httpReason(status) + (DeliveryDiagnostics.serviceCode(code).map { "\n服务错误码：\($0)" } ?? "")
    }
}

struct DeliveryStepError: Error, LocalizedError {
    let stage: String
    let reason: String
    var attachmentNumber: Int?
    var attachmentCount: Int?
    var errorDescription: String? {
        let item = attachmentNumber.map { "（第 \($0)/\(attachmentCount ?? $0) 个附件）" } ?? ""
        return "\(stage)失败\(item)\n\(reason)"
    }
}

enum DeliveryDiagnostics {
    static func step(_ error: Error, stage: String, attachmentNumber: Int? = nil, attachmentCount: Int? = nil) -> DeliveryStepError {
        var result = (error as? DeliveryStepError) ?? DeliveryStepError(stage: stage, reason: reason(error))
        if let attachmentNumber { result.attachmentNumber = attachmentNumber; result.attachmentCount = attachmentCount }
        return result
    }

    static func reason(_ error: Error) -> String {
        if let error = error as? AttachmentHTTPError { return error.localizedDescription }
        if let error = error as? DeliveryStepError { return error.localizedDescription }
        if let error = error as? PortalError {
            if case .http(let status) = error { return httpReason(status) }
            return sanitized(error.localizedDescription)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            let hint: String
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: hint = "网络未连接，请检查 Wi-Fi 或蜂窝网络后重试。"
            case NSURLErrorTimedOut: hint = "请求超时，请切换网络或稍后重试。"
            case NSURLErrorNetworkConnectionLost: hint = "网络连接中断，请恢复网络后重试。"
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: hint = "无法连接服务，请检查网络或稍后重试。"
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted: hint = "无法建立安全连接，请检查设备时间或联系服务维护者。"
            default: hint = "网络请求未完成，请稍后重试。"
            }
            return hint + "（网络错误 \(ns.code)）"
        }
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoSuchFileError: return "本地附件不存在，请重新选择图片或文件后发送。"
            case NSFileReadNoPermissionError: return "无法读取本地附件，请重新选择图片或文件后发送。"
            case NSFileWriteOutOfSpaceError: return "设备存储空间不足，请清理空间后重试。"
            case NSPropertyListReadCorruptError: return "数据格式无法解析，请稍后重试；若持续失败，请联系服务维护者。"
            default: return "数据读取或保存失败（错误 \(ns.code)），请重试。"
            }
        }
        return "操作未完成（错误 \(ns.code)），请重试；若持续失败，请复制错误信息反馈。"
    }

    static func httpReason(_ status: Int) -> String {
        let hint: String
        switch status {
        case 401: hint = "服务未接受当前凭据，请检查 Being 连接或重新连接。"
        case 403: hint = "服务拒绝访问，请确认当前连接具有附件或消息访问权限。"
        case 404: hint = "请求的服务或资源不存在，请联系服务维护者确认。"
        case 413: hint = "服务拒绝了过大的请求，请减少附件数量或缩小文件后重新发送。"
        case 415: hint = "服务不支持该文件格式，请转为 JPEG 或 PNG 后重新发送。"
        case 429: hint = "请求过于频繁或额度受限，请稍后重试。"
        case 500...599: hint = "服务暂时不可用，请稍后重试；若持续失败，请联系服务维护者。"
        default: hint = "服务未能处理请求，请重试；若持续失败，请复制错误信息反馈。"
        }
        return "\(hint)（HTTP \(status)）"
    }

    static func serviceCode(_ value: Any?) -> String? {
        guard let value = value as? String,
              value.range(of: "^[a-zA-Z][a-zA-Z0-9_]{1,63}$", options: .regularExpression) != nil else { return nil }
        return value
    }

    static func serviceCode(from data: Data) -> String? {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let nested = value["error"] as? [String: Any]
        return serviceCode(value["error_code"]) ?? serviceCode(value["code"]) ?? serviceCode(nested?["code"]) ?? serviceCode(value["error"])
    }

    // Old queue entries can contain transport descriptions. Never copy signed
    // URLs or credentials into the screenshot-friendly diagnostic text.
    static func sanitized(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "(?i)(?:https?|file)://[^\\s\"'<>]+", with: "[地址已隐藏]", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)Bearer\\s+[^\\s\"'<>]+", with: "Bearer [已隐藏]", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)((?:token|secret|signature|authorization|credential)[\\w-]*[\"']?\\s*[=:]\\s*[\"']?)[^\\s&,;\"'}]+", with: "$1[已隐藏]", options: .regularExpression)
        return String(result.prefix(1200))
    }

    static func detail(_ entry: PendingSend) -> String {
        sanitized(entry.error ?? (entry.phase == "unknown" ? "暂时无法确认服务是否已收到消息，请核对结果后再重试。" : "未记录具体原因，请重试；若再次失败，请复制错误信息反馈。"))
    }

    static func report(_ entry: PendingSend, version: String) -> String {
        let files = entry.files.enumerated().map { "附件 \($0.offset + 1)：\($0.element.mime)，\($0.element.size) 字节" }
        return sanitized((["Being iOS \(version)", "消息编号：\(entry.id)", "状态：\(entry.phase)", detail(entry)] + files).joined(separator: "\n"))
    }
}

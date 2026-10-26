import Foundation
import EventKit
import Contacts
import CoreLocation

@MainActor final class IOSPortalNative: NSObject, IOSPortalPermissions, @preconcurrency CLLocationManagerDelegate {
    lazy var events = EKEventStore()
    lazy var contacts = CNContactStore()
    let location = CLLocationManager()
    private var locationReply: CheckedContinuation<[String: Any], Error>?
    private var locationTimeout: Task<Void, Never>?
    override init() { super.init(); location.delegate = self; location.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    private var authorizationReply: CheckedContinuation<Void, Error>?
    var permissionChanged: (() -> Void)?
    func available(_ capability: String) -> Bool { permission(capability).available }
    func status(_ capability: String) -> String { permission(capability).label }
    func permission(_ capability: String) -> IOSPortalPermissionState {
        switch capability {
        case "calendar", "reminders":
            let value = EKEventStore.authorizationStatus(for: capability == "calendar" ? .event : .reminder)
            if #available(iOS 17.0, *) {
                if value == .fullAccess { return .allowed }
                if value == .writeOnly { return .writeOnly }
            } else if value == .authorized { return .allowed }
            if value == .notDetermined { return .notDetermined }
            return value == .restricted ? .restricted : .denied
        case "contacts":
            let value = CNContactStore.authorizationStatus(for: .contacts)
            if #available(iOS 18.0, *), value == .limited { return .limited }
            if value == .authorized { return .allowed }
            if value == .notDetermined { return .notDetermined }
            return value == .restricted ? .restricted : .denied
        case "location":
            // authorizationStatus also reports denied when system Location Services are off.
            // Avoid the synchronous service query on the UI thread.
            switch location.authorizationStatus {
            case .notDetermined: return .notDetermined
            case .restricted: return .restricted
            case .denied: return .denied
            case .authorizedAlways, .authorizedWhenInUse:
                return location.accuracyAuthorization == .reducedAccuracy ? .approximate : .allowed
            @unknown default: return .unavailable
            }
        default: return .unavailable
        }
    }
    func authorize(_ capability: String) async throws {
        switch capability {
        case "calendar":
            let granted: Bool
            if #available(iOS 17.0, *) { granted = try await events.requestFullAccessToEvents() }
            else { granted = try await events.requestAccess(to: .event) }
            guard granted else { throw PortalError.server("日历权限未授予。") }; events.reset()
        case "reminders":
            let granted: Bool
            if #available(iOS 17.0, *) { granted = try await events.requestFullAccessToReminders() }
            else { granted = try await events.requestAccess(to: .reminder) }
            guard granted else { throw PortalError.server("提醒事项权限未授予。") }; events.reset()
        case "contacts":
            guard try await contacts.requestAccess(for: .contacts) else { throw PortalError.server("通讯录权限未授予。") }
        case "location":
            if available("location") { return }
            guard permission("location") == .notDetermined, authorizationReply == nil else { throw PortalError.server("请在系统设置中允许定位。") }
            try await withCheckedThrowingContinuation { continuation in
                authorizationReply = continuation
                location.requestWhenInUseAuthorization()
            }
        default: break
        }
    }
    func read(_ capability: String, _ args: [String: Any]) async throws -> [String: Any] {
        let action = args["action"] as? String ?? "list"
        switch capability {
        case "calendar":
            if action == "calendars" { return ["calendars": calendars(.event)] }
            if action == "get" {
                guard let event = events.event(withIdentifier: try LocalPortalRules.string(args, "id")) else { throw PortalError.server("日程不存在。") }
                return eventJSON(event)
            }
            guard action == "list" else { throw PortalError.server("不支持的日历操作。") }
            let start = try LocalPortalRules.date(args, "start"), end = try LocalPortalRules.date(args, "end")
            guard end > start, end.timeIntervalSince(start) <= 366 * 86400 else { throw PortalError.server("查询时间范围需在 366 天内。") }
            let calendar = try selectedCalendars(args, type: .event)
            let result = events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: calendar))

            let query = args["query"] as? String ?? ""
            let filtered = result.filter { query.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(query) }
            return ["events": filtered.prefix(200).map(eventJSON), "truncated": filtered.count > 200]
        case "reminders":
            if action == "calendars" { return ["calendars": calendars(.reminder)] }
            if action == "get" {
                guard let item = events.calendarItem(withIdentifier: try LocalPortalRules.string(args, "id")) as? EKReminder else { throw PortalError.server("提醒事项不存在。") }
                return reminderJSON(item)
            }
            guard action == "list" else { throw PortalError.server("不支持的提醒操作。") }
            let selected = try selectedCalendars(args, type: .reminder)
            let predicate = events.predicateForReminders(in: selected)
            let reminders: [EKReminder] = await withCheckedContinuation { continuation in
                events.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
            }
            try Task.checkCancellation()
            let query = args["query"] as? String ?? ""
            let filtered = reminders.filter { query.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(query) }
                .filter { item in (args["completed"] as? Bool).map { item.isCompleted == $0 } ?? true }
                .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
            return ["reminders": filtered.prefix(200).map(reminderJSON), "truncated": filtered.count > 200]
        case "contacts":
            let keys = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
            if action == "get" { return contactJSON(try contacts.unifiedContact(withIdentifier: LocalPortalRules.string(args, "id"), keysToFetch: keys)) }
            guard action == "list" else { throw PortalError.server("不支持的通讯录操作。") }
            let request = CNContactFetchRequest(keysToFetch: keys); request.sortOrder = .userDefault
            let query = (args["query"] as? String ?? "").lowercased()
            var result = [[String: Any]](); var truncated = false
            try contacts.enumerateContacts(with: request) { contact, stop in
                let values = [contact.givenName, contact.familyName] + contact.phoneNumbers.map { $0.value.stringValue } + contact.emailAddresses.map { String($0.value) }
                if query.isEmpty || values.joined(separator: " ").lowercased().contains(query) {
                    if result.count == 200 { truncated = true; stop.pointee = true } else { result.append(self.contactJSON(contact)) }
                }
            }
            return ["contacts": result, "truncated": truncated, "system_access": status("contacts")]
        case "location":
            guard action == "get" else { throw PortalError.server("定位仅支持 get。") }
            guard locationReply == nil else { throw PortalError.server("已有定位请求，请稍后重试。") }
            return try await withCheckedThrowingContinuation { continuation in
                locationReply = continuation
                location.requestLocation()
                locationTimeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    self?.finishLocation(.failure(PortalError.server("定位超时，请稍后重试。")))
                }
            }
        default: throw PortalError.server("不支持的原生能力。")
        }
    }
    func validateWrite(_ capability: String, _ args: [String: Any]) throws {
        let action = try LocalPortalRules.string(args, "action")
        guard ["create", "update", "delete"].contains(action), ["calendar", "reminders", "contacts"].contains(capability) else { throw PortalError.server("不支持的写操作。") }
        if action != "create" { _ = try LocalPortalRules.string(args, "id") }
        if action == "delete" { return }
        if capability == "contacts" {
            if action == "create" || args["given_name"] != nil { _ = try LocalPortalRules.string(args, "given_name", max: 256) }
            for key in ["phones", "emails"] where args[key] != nil {
                guard let values = args[key] as? [String], values.count <= 20, values.allSatisfy({ !$0.isEmpty && $0.count <= 256 }) else { throw PortalError.server("\(key) 需为最多 20 项的文字数组。") }
            }
        } else {
            if action == "create" || args["title"] != nil { _ = try LocalPortalRules.string(args, "title", max: 500) }
            if capability == "calendar" {
                // Require both dates for updates so an invalid interval never reaches EventKit.
                let start = try LocalPortalRules.date(args, "start"), end = try LocalPortalRules.date(args, "end")
                guard end > start, end.timeIntervalSince(start) <= 366 * 86400 else { throw PortalError.server("日程结束时间需晚于开始，且不超过 366 天。") }
            }
            if args["due"] != nil { _ = try LocalPortalRules.date(args, "due") }
        }
        if let notes = args["notes"] as? String, notes.count > 10000 { throw PortalError.server("备注过长。") }
    }
    /// These details stay on the phone for review; actions polling never returns them.
    func preview(_ capability: String, _ args: [String: Any]) throws -> [String: String] {
        if args["action"] as? String == "create" {
            if capability == "calendar" || capability == "reminders" {
                let calendar = try writeCalendar(args, capability == "calendar" ? .event : .reminder)
                return ["目标日历": calendar.title, "日历 ID": calendar.calendarIdentifier]
            }
            return [:]
        }
        let id = try LocalPortalRules.string(args, "id")
        switch capability {
        case "calendar":
            guard let event = events.event(withIdentifier: id) else { throw PortalError.server("日程不存在。") }
            guard !event.hasRecurrenceRules, (event.attendees ?? []).isEmpty else { throw PortalError.server("重复日程或有参与者的日程请在日历 App 中修改。") }
            return ["标题": event.title ?? "", "开始时间": event.startDate.ISO8601Format(), "结束时间": event.endDate.ISO8601Format(), "日历": event.calendar.title, "备注": event.notes ?? ""]
        case "reminders":
            guard let item = events.calendarItem(withIdentifier: id) as? EKReminder else { throw PortalError.server("提醒事项不存在。") }
            guard !item.hasRecurrenceRules else { throw PortalError.server("重复提醒请在提醒事项 App 中修改。") }
            return ["标题": item.title ?? "", "提醒时间": item.dueDateComponents?.date?.ISO8601Format() ?? "无", "已完成": item.isCompleted ? "是" : "否", "备注": item.notes ?? ""]
        case "contacts":
            let contact = try contacts.unifiedContact(withIdentifier: id, keysToFetch: [CNContactViewControllerDescriptor.descriptor])
            return ["名字": contact.givenName, "姓氏": contact.familyName, "电话": contact.phoneNumbers.map { $0.value.stringValue }.joined(separator: "\n"), "邮箱": contact.emailAddresses.map { String($0.value) }.joined(separator: "\n")]
        default: throw PortalError.server("不支持的原生能力。")
        }
    }
    func write(_ capability: String, _ args: [String: Any]) throws -> [String: Any] {
        try validateWrite(capability, args)
        let action = args["action"] as! String, id = args["id"] as? String ?? ""
        switch capability {
        case "calendar":
            let item: EKEvent
            if action == "create" { item = EKEvent(eventStore: events); item.calendar = try writeCalendar(args, .event) }
            else { guard let existing = events.event(withIdentifier: id) else { throw PortalError.server("日程不存在。") }; item = existing }
            guard item.calendar.allowsContentModifications else { throw PortalError.server("此日历只读。") }
            // Avoid accidental whole-series changes or invitations sent to attendees.
            guard !item.hasRecurrenceRules, (item.attendees ?? []).isEmpty else { throw PortalError.server("重复日程或有参与者的日程请在日历 App 中修改。") }
            if action == "delete" { try events.remove(item, span: .thisEvent, commit: true); return ["deleted": true, "id": id] }
            if let title = args["title"] as? String { item.title = title }
            if let notes = args["notes"] as? String { item.notes = notes }
            item.startDate = try LocalPortalRules.date(args, "start"); item.endDate = try LocalPortalRules.date(args, "end")
            if let allDay = args["all_day"] as? Bool { item.isAllDay = allDay }
            try events.save(item, span: .thisEvent, commit: true)
            return ["id": item.eventIdentifier ?? "", "saved": true]
        case "reminders":
            let item: EKReminder
            if action == "create" { item = EKReminder(eventStore: events); item.calendar = try writeCalendar(args, .reminder) }
            else { guard let existing = events.calendarItem(withIdentifier: id) as? EKReminder else { throw PortalError.server("提醒事项不存在。") }; item = existing }
            guard item.calendar.allowsContentModifications, !item.hasRecurrenceRules else { throw PortalError.server("只读或重复提醒请在提醒事项 App 中修改。") }
            if action == "delete" { try events.remove(item, commit: true); return ["deleted": true, "id": id] }
            if let title = args["title"] as? String { item.title = title }
            if let notes = args["notes"] as? String { item.notes = notes }
            if args["due"] != nil {
                let date = try LocalPortalRules.date(args, "due")
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                item.dueDateComponents = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: date)
                item.alarms = [EKAlarm(absoluteDate: date)]
            }
            if let complete = args["completed"] as? Bool { item.isCompleted = complete }
            try events.save(item, commit: true)
            return ["id": item.calendarItemIdentifier, "saved": true]
        case "contacts":
            let item: CNMutableContact
            if action == "create" { item = CNMutableContact() }
            else {
                let keys = [CNContactViewControllerDescriptor.descriptor]
                item = try contacts.unifiedContact(withIdentifier: id, keysToFetch: keys).mutableCopy() as! CNMutableContact
            }
            let request = CNSaveRequest()
            if action == "delete" { request.delete(item) }
            else {
                if let name = args["given_name"] as? String { item.givenName = name }
                if let name = args["family_name"] as? String { item.familyName = name }
                if let values = args["phones"] as? [String] { item.phoneNumbers = values.map { CNLabeledValue(label: CNLabelOther, value: CNPhoneNumber(stringValue: $0)) } }
                if let values = args["emails"] as? [String] { item.emailAddresses = values.map { CNLabeledValue(label: CNLabelOther, value: $0 as NSString) } }
                if action == "create" { request.add(item, toContainerWithIdentifier: nil) } else { request.update(item) }
            }
            try contacts.execute(request)
            return ["id": item.identifier, "deleted": action == "delete", "saved": action != "delete"]
        default: throw PortalError.server("不支持的原生写操作。")
        }
    }
    private func calendars(_ type: EKEntityType) -> [[String: Any]] {
        events.calendars(for: type).map { ["id": $0.calendarIdentifier, "title": $0.title, "writable": $0.allowsContentModifications] }
    }
    private func selectedCalendars(_ args: [String: Any], type: EKEntityType) throws -> [EKCalendar]? {
        guard let id = args["calendar_id"] as? String else { return nil }
        guard let calendar = events.calendars(for: type).first(where: { $0.calendarIdentifier == id }) else { throw PortalError.server("日历不存在。") }
        return [calendar]
    }
    private func writeCalendar(_ args: [String: Any], _ type: EKEntityType) throws -> EKCalendar {
        let calendar = try selectedCalendars(args, type: type)?.first ?? (type == .event ? events.defaultCalendarForNewEvents : events.defaultCalendarForNewReminders())
        guard let calendar, calendar.allowsContentModifications else { throw PortalError.server("没有可写入的日历，请先在系统 App 中创建。") }
        return calendar
    }
    private func eventJSON(_ event: EKEvent) -> [String: Any] {
        ["id": event.eventIdentifier ?? "", "title": event.title ?? "", "start": event.startDate.ISO8601Format(), "end": event.endDate.ISO8601Format(), "all_day": event.isAllDay, "calendar_id": event.calendar.calendarIdentifier, "recurring": event.hasRecurrenceRules]
    }
    private func reminderJSON(_ item: EKReminder) -> [String: Any] {
        var result: [String: Any] = ["id": item.calendarItemIdentifier, "title": item.title ?? "", "completed": item.isCompleted, "calendar_id": item.calendar.calendarIdentifier]
        if let due = item.dueDateComponents?.date { result["due"] = due.ISO8601Format() }; return result
    }
    private func contactJSON(_ item: CNContact) -> [String: Any] {
        ["id": item.identifier, "given_name": item.givenName, "family_name": item.familyName, "phones": item.phoneNumbers.map { $0.value.stringValue }, "emails": item.emailAddresses.map { String($0.value) }]
    }
    func cancelLocation() { finishLocation(.failure(CancellationError())) }
    private func finishLocation(_ result: Result<[String: Any], Error>) {
        locationTimeout?.cancel(); locationTimeout = nil
        let reply = locationReply; locationReply = nil; reply?.resume(with: result)
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined, let reply = authorizationReply {
            authorizationReply = nil
            if available("location") { reply.resume() }
            else { reply.resume(throwing: PortalError.server("定位权限未授予。")) }
        }
        permissionChanged?()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let point = locations.last, point.horizontalAccuracy >= 0, abs(point.timestamp.timeIntervalSinceNow) < 60 else { return }
        finishLocation(.success(["latitude": point.coordinate.latitude, "longitude": point.coordinate.longitude, "accuracy_m": point.horizontalAccuracy, "timestamp": point.timestamp.ISO8601Format(), "reduced_accuracy": manager.accuracyAuthorization == .reducedAccuracy]))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finishLocation(.failure(PortalError.server("无法取得位置，请检查定位权限和系统定位服务。"))) }
}

// Fetch all writable contact fields so a partial update preserves unrelated data.
import ContactsUI
private enum CNContactViewControllerDescriptor {
    static var descriptor: CNKeyDescriptor { CNContactViewController.descriptorForRequiredKeys() }
}

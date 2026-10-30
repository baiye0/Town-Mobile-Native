import SwiftUI

extension SocialStore {
    func importIdentity(id: String, token: String) async throws {
        let expected = try TownContracts.identity(id)
        try TownContracts.validatePair(input: expected, townID: expected.hasPrefix("t_") ? expected : nil, beingID: expected.hasPrefix("t_") ? nil : expected, token: token)
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForResource = 20
        let probe = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil); defer { probe.invalidateAndCancel() }
        var url = URLComponents(string: "https://beings.town/api/client/stream")!; url.queryItems = [URLQueryItem(name:"token",value:token)]
        var req = URLRequest(url:url.url!); req.setValue("text/event-stream", forHTTPHeaderField:"Accept")
        let (bytes,response) = try await probe.bytes(for:req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PortalError.server("凭据验证失败。") }
        var parser = SSEByteParser(), count = 0
        for try await byte in bytes {
            try Task.checkCancellation(); count += 1; guard count <= 65536 else { throw PortalError.invalidResponse }
            guard let event = try parser.consume(byte), event.name == "hello", let data = event.data.data(using:.utf8), let hello = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { continue }
            let actual = field(hello,"town_id","being_id")
            guard hello["anonymous"] as? Bool == false, hello["token_kind"] as? String == "client", actual == expected || !expected.hasPrefix("t_") && hello["being_id"] as? String == expected else { throw PortalError.server("凭据与填写的小镇身份不一致。") }
            let value = TownIdentity(token:token,id:actual,name:field(hello,"display_name","display"))
            try TownVault.save(value); stopLive(); identity = value; resetUnread(); revision += 1; startLive(); return
        }
        throw PortalError.server("未收到小镇身份确认。")
    }
}
struct AdvancedPairing: View {
    @EnvironmentObject private var social: SocialStore
    @State private var id = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void,Never>?
    var body: some View {
        DisclosureGroup("导入已有 Town 凭据") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Town ID 或 Being 名", text:$id).textInputAutocapitalization(.never).autocorrectionDisabled().settingsInput()
                SecureField("Town client token", text:$token).textInputAutocapitalization(.never).autocorrectionDisabled().settingsInput()
                Button(busy ? "正在验证…" : "验证并导入") {
                    busy = true; error = nil
                    task = Task { defer { busy = false }; do { try await social.importIdentity(id:id.trimmingCharacters(in:.whitespacesAndNewlines),token:token.trimmingCharacters(in:.whitespacesAndNewlines)); token = "" } catch { if !Task.isCancelled { self.error = error.localizedDescription } } }
                }.buttonStyle(SettingsActionStyle()).disabled(busy || id.isEmpty || token.isEmpty)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }.padding(.top, 14)
        }.onDisappear { task?.cancel() }
    }
}

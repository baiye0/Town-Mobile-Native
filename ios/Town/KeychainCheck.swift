#if DEBUG && targetEnvironment(simulator)
import Foundation
import Security
/// Simulator-only verification; never reads or overwrites a user's credentials.
enum KeychainCheck {
    static func run() {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"beings.qa." + UUID().uuidString,kSecAttrAccount as String:"test"]
        var item = query; item[kSecValueData as String] = Data("test".utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let add = SecItemAdd(item as CFDictionary,nil)
        let update = SecItemUpdate(query as CFDictionary,[kSecValueData as String:Data("updated".utf8)] as CFDictionary)
        var read = query; read[kSecReturnData as String] = true
        var value: CFTypeRef?; let get = SecItemCopyMatching(read as CFDictionary,&value)
        let correct = (value as? Data) == Data("updated".utf8)
        let delete = SecItemDelete(query as CFDictionary)
        let result = "add=\(add) update=\(update) read=\(get) value=\(correct) delete=\(delete)"
        try? result.write(to: URL.documentsDirectory.appending(path:"keychain-check.txt"),atomically:true,encoding:.utf8)
    }
}
#endif

import Foundation
import Security
import SwiftUI
import UserNotifications

/// The museum's private date-service settings. Only the service origin goes to UserDefaults.
/// The bearer credential stays in the device's Keychain.
struct HostConfig {
    let apiBase: String
    let credential: String

    static let defaultsKey = "museum.ephemera.apiBase"

    static func validateOrigin(_ raw: String) -> String? {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "https",
              let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { return nil }
        // A private server may live under a dedicated reverse-proxy prefix
        // such as https://example.org/date. Reject encoded paths and traversal.
        let path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty && path.range(
            of: "^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$",
            options: .regularExpression
        ) == nil { return nil }
        var value = "https://\(host.lowercased())"
        if let port = c.port { value += ":\(port)" }
        if !path.isEmpty { value += "/" + path }
        return value
    }

    static func load() -> HostConfig {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return HostConfig(apiBase: validateOrigin(raw) ?? "",
                          credential: MuseumKeychain.read() ?? "")
    }

    var isConfigured: Bool { !apiBase.isEmpty && !credential.isEmpty }
    // Native bridge enabled from the first load. The credential is NEVER in the URL.
    var pageURL: String { apiBase + "/app/?embed=native" }
    var resolvedAPIBase: String { apiBase }
    var galleryURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: apiBase + "/museum-gallery/")
    }
    var sessionURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: apiBase + "/museum-gallery/session")
    }
    var syncURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: apiBase + "/museum-gallery/sync")
    }

}

enum MuseumKeychain {
    private static let service = "com.zfxf.museum.ephemera"
    private static let account = "herCredential"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        let search: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            let status = SecItemDelete(search as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        var attributes = search
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(search as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
}

final class HostState: ObservableObject {
    static let shared = HostState()
    @Published private(set) var config = HostConfig.load()
    @Published var pageOpen = false
    var pendingRoute: [String: Any]?
    var navigateOpenPage: (([String: Any]) -> Void)?

    /// Upstream controller calls this. Do not log our private date names,
    /// memory content, navigation payloads, or credentials to Console.
    func record(_ message: String) { /* intentionally private */ }

    @discardableResult
    func saveConnection(origin: String, credential: String) -> Bool {
        guard let validated = HostConfig.validateOrigin(origin),
              !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              MuseumKeychain.save(credential) else { return false }
        UserDefaults.standard.set(validated, forKey: HostConfig.defaultsKey)
        config = HostConfig.load()
        return config.isConfigured
    }

    func removeConnection() {
        guard !pageOpen else { return }
        guard MuseumKeychain.save("") else { return }
        UserDefaults.standard.removeObject(forKey: HostConfig.defaultsKey)
        config = HostConfig.load()
    }

    func open(route: [String: Any]?) {
        guard config.isConfigured else { return }
        if pageOpen, let route, let navigateOpenPage {
            navigateOpenPage(route)
            return
        }
        pendingRoute = route
        pageOpen = true
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    func notify(kind: String, planId: Int?) {
        let content = UNMutableNotificationContent()
        content.title = "ZFxF · Ephemera"
        content.body = Self.eventText[kind] ?? "约会纪念馆有新消息"
        content.sound = nil
        var info: [String: Any] = ["page": Self.eventPage[kind] ?? "seal"]
        if let planId { info["planId"] = planId }
        content.userInfo = info
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString,
                                  content: content, trigger: nil))
    }

    private static let eventText: [String: String] = [
        "envelope": "一封新邀请函",
        "telegram_manual": "收到一封电报",
        "telegram_auto": "收到一封电报",
        "cancel": "约会计划有变化",
        "close": "一场约会收进了纪念盒",
        "late_written": "纪念盒有新内容"
    ]
    private static let eventPage: [String: String] = [
        "envelope": "seal", "telegram_manual": "telegrams",
        "telegram_auto": "telegrams", "cancel": "telegrams",
        "close": "box", "late_written": "box"
    ]
}

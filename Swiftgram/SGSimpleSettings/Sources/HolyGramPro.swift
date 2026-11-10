// MARK: HolyGram Pro
import Foundation
import CryptoKit
import Security

/// HolyGram Pro belongs to one iPhone: the server keys subscriptions by a device code that this
/// app generates once and keeps in the device-only keychain. On this iPhone Pro works in every
/// account; the same Telegram account logged in elsewhere doesn't carry it over. Each status is
/// signed with the server's Ed25519 key, so it can't be forged by a proxy or by editing settings.
public final class HolyGramPro {
    public static let shared = HolyGramPro()

    // While serverURL or publicKeyBase64 is empty, Pro checks are off and every Pro feature is
    // available, so development builds keep working.
    public static let serverURL = "https://holygram-pro.holygram.workers.dev"
    public static let publicKeyBase64 = "e2sgxBM+seP6hrXgPIq5ErBiI15xH7HhhA3wVJGP3Sg="
    /// Bot users write to for buying or renewing Pro, without "@".
    public static let botUsername = "HolygramBot"

    /// How long a signed status is trusted without reaching the server.
    private static let maxStatusAge: TimeInterval = 3 * 86400
    private static let refreshInterval: TimeInterval = 6 * 3600
    private static let storageKey = "holygram_pro_status_v2"
    private static let flagsStorageKey = "holygram_pro_flags_v1"

    public static let didChangeNotification = Notification.Name("HolyGramProDidChange")

    public struct Status: Codable, Equatable {
        public let device: String
        /// -1 forever, 0 none, otherwise unix seconds.
        public let expiresAt: Int64
        public let issuedAt: Int64
        let payload: String
        let signature: String

        public func isActive(now: Date = Date()) -> Bool {
            let nowSeconds = Int64(now.timeIntervalSince1970)
            if Double(nowSeconds - self.issuedAt) > HolyGramPro.maxStatusAge {
                return false
            }
            return self.expiresAt == -1 || self.expiresAt > nowSeconds
        }
    }

    private let queue = DispatchQueue(label: "HolyGramPro")
    private var currentStatus: Status?
    private var lastRefresh: Date?
    /// Features switched off for everyone from the admin bot (/disable), e.g. on a request from Telegram.
    private var disabledFeatures: Set<String> = []

    /// "HG" + 12 Crockford base32 characters, e.g. HG7K2F9XQMP4TD.
    public let deviceCode: String

    /// "HG-7K2F-9XQM-P4TD"
    public var displayDeviceCode: String {
        let body = Array(self.deviceCode.dropFirst(2))
        guard body.count == 12 else {
            return self.deviceCode
        }
        return "HG-\(String(body[0 ..< 4]))-\(String(body[4 ..< 8]))-\(String(body[8 ..< 12]))"
    }

    public var isConfigured: Bool {
        return !HolyGramPro.serverURL.isEmpty && HolyGramPro.publicKey != nil
    }

    private static let publicKey: Curve25519.Signing.PublicKey? = {
        guard let data = Data(base64Encoded: HolyGramPro.publicKeyBase64) else {
            return nil
        }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: data)
    }()

    private init() {
        self.deviceCode = HolyGramDeviceCode.load()
        if let stored = UserDefaults.standard.array(forKey: HolyGramPro.storageKey) as? [String], stored.count == 2, let status = HolyGramPro.verify(payload: stored[0], signature: stored[1]), status.device == self.deviceCode {
            self.currentStatus = status
        }
        if let stored = UserDefaults.standard.array(forKey: HolyGramPro.flagsStorageKey) as? [String], stored.count == 2, let flags = HolyGramPro.verifyFlags(payload: stored[0], signature: stored[1]) {
            self.disabledFeatures = flags
        }
    }

    /// True when this iPhone has an active subscription.
    public var isActive: Bool {
        if !self.isConfigured {
            return true
        }
        return self.queue.sync {
            self.currentStatus?.isActive() ?? false
        }
    }

    public var status: Status? {
        return self.queue.sync { self.currentStatus }
    }

    /// "ghost", "selfdestruct", "deleted", "edits".
    public func isRemotelyDisabled(_ feature: String) -> Bool {
        return self.queue.sync { self.disabledFeatures.contains(feature) }
    }

    /// Link that opens the bot with this device's code, so the admin gets a request.
    public var botRequestUrl: String {
        return "https://t.me/\(HolyGramPro.botUsername)?start=\(self.deviceCode)"
    }

    /// Checks the subscription and the remote switches; without `force` at most every 6 hours.
    public func refresh(force: Bool = false) {
        guard self.isConfigured else {
            return
        }
        let shouldFetch: Bool = self.queue.sync {
            if !force, let last = self.lastRefresh, Date().timeIntervalSince(last) < HolyGramPro.refreshInterval {
                return false
            }
            self.lastRefresh = Date()
            return true
        }
        if shouldFetch {
            self.fetchStatus()
            self.fetchFlags()
        }
    }

    private func request(path: String, query: [URLQueryItem] = [], completion: @escaping (_ payload: String, _ signature: String) -> Void) {
        guard var components = URLComponents(string: HolyGramPro.serverURL) else {
            return
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0), completionHandler: { data, _, _ in
            guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = object["payload"] as? String, let signature = object["sig"] as? String else {
                return
            }
            completion(payload, signature)
        }).resume()
    }

    private func fetchStatus() {
        let deviceCode = self.deviceCode
        self.request(path: "/v1/status", query: [URLQueryItem(name: "device", value: deviceCode)], completion: { [weak self] payload, signature in
            guard let self, let status = HolyGramPro.verify(payload: payload, signature: signature), status.device == deviceCode else {
                return
            }
            let changed: Bool = self.queue.sync {
                let previous = self.currentStatus
                self.currentStatus = status
                UserDefaults.standard.set([payload, signature], forKey: HolyGramPro.storageKey)
                return previous?.expiresAt != status.expiresAt || previous?.isActive() != status.isActive()
            }
            if changed {
                HolyGramPro.notifyChanged()
            }
        })
    }

    private func fetchFlags() {
        self.request(path: "/v1/flags", completion: { [weak self] payload, signature in
            guard let self, let flags = HolyGramPro.verifyFlags(payload: payload, signature: signature) else {
                return
            }
            let changed: Bool = self.queue.sync {
                let changed = self.disabledFeatures != flags
                self.disabledFeatures = flags
                UserDefaults.standard.set([payload, signature], forKey: HolyGramPro.flagsStorageKey)
                return changed
            }
            if changed {
                HolyGramPro.notifyChanged()
            }
        })
    }

    private static func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: HolyGramPro.didChangeNotification, object: nil)
        }
    }

    private static func isValid(payload: String, signature: String) -> Bool {
        guard let publicKey = HolyGramPro.publicKey, let signatureData = Data(base64Encoded: signature) else {
            return false
        }
        return publicKey.isValidSignature(signatureData, for: Data(payload.utf8))
    }

    /// Parses and checks "holygram-flags-v1|<disabled,features>|<issuedAt>".
    static func verifyFlags(payload: String, signature: String) -> Set<String>? {
        guard HolyGramPro.isValid(payload: payload, signature: signature) else {
            return nil
        }
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "holygram-flags-v1" else {
            return nil
        }
        return Set(parts[1].split(separator: ",").map(String.init))
    }

    /// Parses and checks "holygram-pro-v2|<deviceCode>|<expiresAt>|<issuedAt>".
    static func verify(payload: String, signature: String) -> Status? {
        guard HolyGramPro.isValid(payload: payload, signature: signature) else {
            return nil
        }
        let parts = payload.split(separator: "|").map(String.init)
        guard parts.count == 4, parts[0] == "holygram-pro-v2", let expiresAt = Int64(parts[2]), let issuedAt = Int64(parts[3]) else {
            return nil
        }
        return Status(device: parts[1], expiresAt: expiresAt, issuedAt: issuedAt, payload: payload, signature: signature)
    }
}

/// The device code lives in the keychain with a ThisDeviceOnly accessibility, so it survives a
/// reinstall but is never synced through iCloud Keychain or restored onto another iPhone.
private enum HolyGramDeviceCode {
    private static let service = "holygram.pro.device"
    private static let account = "device-code"
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let code = String(data: data, encoding: .utf8), code.count == 14, code.hasPrefix("HG") {
            return code
        }
        let code = generate()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(code.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
        return code
    }

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 12)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in 0 ..< bytes.count {
                bytes[i] = UInt8.random(in: 0 ... 255)
            }
        }
        return "HG" + String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
}

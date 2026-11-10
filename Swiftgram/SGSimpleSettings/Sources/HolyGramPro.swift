// MARK: HolyGram Pro
import Foundation
import CryptoKit

/// Subscription status checked against the HolyGram Pro server. Each status is signed with the
/// server's Ed25519 key, so it can't be forged by a proxy or by editing stored settings.
public final class HolyGramPro {
    public static let shared = HolyGramPro()

    // Filled in once the server is deployed (server/README.md). While empty, Pro checks are off
    // and every Pro feature is available, so development builds keep working.
    public static let serverURL = ""
    public static let publicKeyBase64 = ""
    /// Bot users write to for buying or renewing Pro, without "@".
    public static let botUsername = ""

    /// How long a signed status is trusted without reaching the server.
    private static let maxStatusAge: TimeInterval = 3 * 86400
    private static let refreshInterval: TimeInterval = 6 * 3600
    private static let storageKey = "holygram_pro_statuses_v1"
    private static let flagsStorageKey = "holygram_pro_flags_v1"

    public static let didChangeNotification = Notification.Name("HolyGramProDidChange")

    public struct Status: Codable, Equatable {
        public let userId: Int64
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
    private var statuses: [Int64: Status] = [:]
    private var lastRefresh: [Int64: Date] = [:]
    private var knownUserIds: [Int64] = []
    /// Features switched off for everyone from the admin bot (/disable), e.g. on a request from Telegram.
    private var disabledFeatures: Set<String> = []
    private var lastFlagsRefresh: Date?

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
        if let stored = UserDefaults.standard.array(forKey: HolyGramPro.flagsStorageKey) as? [String], stored.count == 2, let flags = HolyGramPro.verifyFlags(payload: stored[0], signature: stored[1]) {
            self.disabledFeatures = flags
        }
        if let data = UserDefaults.standard.data(forKey: HolyGramPro.storageKey), let stored = try? JSONDecoder().decode([Status].self, from: data) {
            for status in stored where HolyGramPro.verify(payload: status.payload, signature: status.signature) == status {
                self.statuses[status.userId] = status
            }
        }
    }

    /// True when any account on this device has an active subscription.
    public var isActive: Bool {
        if !self.isConfigured {
            return true
        }
        return self.queue.sync {
            self.statuses.values.contains(where: { $0.isActive() })
        }
    }

    /// "ghost", "selfdestruct", "deleted", "edits".
    public func isRemotelyDisabled(_ feature: String) -> Bool {
        return self.queue.sync { self.disabledFeatures.contains(feature) }
    }

    public func status(userId: Int64) -> Status? {
        return self.queue.sync { self.statuses[userId] }
    }

    /// Called with the user ids of all logged-in accounts; refreshes the ones not checked recently.
    public func refresh(userIds: [Int64], force: Bool = false) {
        guard self.isConfigured else {
            return
        }
        let toFetch: [Int64] = self.queue.sync {
            self.knownUserIds = userIds
            return userIds.filter { userId in
                if force {
                    return true
                }
                guard let last = self.lastRefresh[userId] else {
                    return true
                }
                return Date().timeIntervalSince(last) > HolyGramPro.refreshInterval
            }
        }
        for userId in toFetch {
            self.fetch(userId: userId)
        }
        let fetchFlags: Bool = self.queue.sync {
            if !force, let last = self.lastFlagsRefresh, Date().timeIntervalSince(last) < HolyGramPro.refreshInterval {
                return false
            }
            self.lastFlagsRefresh = Date()
            return true
        }
        if fetchFlags {
            self.fetchFlags()
        }
    }

    private func fetchFlags() {
        guard var components = URLComponents(string: HolyGramPro.serverURL) else {
            return
        }
        components.path = "/v1/flags"
        guard let url = components.url else {
            return
        }
        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0), completionHandler: { [weak self] data, _, _ in
            guard let self, let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = object["payload"] as? String, let signature = object["sig"] as? String, let flags = HolyGramPro.verifyFlags(payload: payload, signature: signature) else {
                return
            }
            let changed: Bool = self.queue.sync {
                let changed = self.disabledFeatures != flags
                self.disabledFeatures = flags
                UserDefaults.standard.set([payload, signature], forKey: HolyGramPro.flagsStorageKey)
                return changed
            }
            if changed {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: HolyGramPro.didChangeNotification, object: nil)
                }
            }
        }).resume()
    }

    public func refreshKnown(force: Bool = false) {
        let ids = self.queue.sync { self.knownUserIds }
        self.refresh(userIds: ids, force: force)
    }

    private func fetch(userId: Int64) {
        guard var components = URLComponents(string: HolyGramPro.serverURL) else {
            return
        }
        components.path = "/v1/status"
        components.queryItems = [URLQueryItem(name: "user_id", value: "\(userId)")]
        guard let url = components.url else {
            return
        }
        self.queue.sync {
            self.lastRefresh[userId] = Date()
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request, completionHandler: { [weak self] data, _, _ in
            guard let self, let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = object["payload"] as? String, let signature = object["sig"] as? String else {
                return
            }
            guard let status = HolyGramPro.verify(payload: payload, signature: signature), status.userId == userId else {
                return
            }
            self.store(status)
        }).resume()
    }

    private func store(_ status: Status) {
        let changed: Bool = self.queue.sync {
            let previous = self.statuses[status.userId]
            self.statuses[status.userId] = status
            if let data = try? JSONEncoder().encode(Array(self.statuses.values)) {
                UserDefaults.standard.set(data, forKey: HolyGramPro.storageKey)
            }
            return previous?.expiresAt != status.expiresAt || previous?.isActive() != status.isActive()
        }
        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: HolyGramPro.didChangeNotification, object: nil)
            }
        }
    }

    /// Parses and checks "holygram-flags-v1|<disabled,features>|<issuedAt>".
    static func verifyFlags(payload: String, signature: String) -> Set<String>? {
        guard let publicKey = HolyGramPro.publicKey, let signatureData = Data(base64Encoded: signature) else {
            return nil
        }
        guard publicKey.isValidSignature(signatureData, for: Data(payload.utf8)) else {
            return nil
        }
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "holygram-flags-v1" else {
            return nil
        }
        return Set(parts[1].split(separator: ",").map(String.init))
    }

    /// Parses and checks "holygram-pro-v1|<userId>|<expiresAt>|<issuedAt>".
    static func verify(payload: String, signature: String) -> Status? {
        guard let publicKey = HolyGramPro.publicKey, let signatureData = Data(base64Encoded: signature) else {
            return nil
        }
        guard publicKey.isValidSignature(signatureData, for: Data(payload.utf8)) else {
            return nil
        }
        let parts = payload.split(separator: "|").map(String.init)
        guard parts.count == 4, parts[0] == "holygram-pro-v1", let userId = Int64(parts[1]), let expiresAt = Int64(parts[2]), let issuedAt = Int64(parts[3]) else {
            return nil
        }
        return Status(userId: userId, expiresAt: expiresAt, issuedAt: issuedAt, payload: payload, signature: signature)
    }
}

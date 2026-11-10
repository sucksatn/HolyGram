// MARK: HolyGram: hidden chats and chats locked with Face ID
import Foundation
import LocalAuthentication

public extension SGSimpleSettings {
    func isHiddenChat(_ peerIdValue: Int64) -> Bool {
        return self.hgPro && self.hiddenChats.contains(String(peerIdValue))
    }

    func setHiddenChat(_ peerIdValue: Int64, _ hidden: Bool) {
        var list = self.hiddenChats.filter { $0 != String(peerIdValue) }
        if hidden {
            list.append(String(peerIdValue))
        }
        self.hiddenChats = list
    }

    func isLockedChat(_ peerIdValue: Int64) -> Bool {
        return self.hgPro && self.lockedChats.contains(String(peerIdValue))
    }

    func setLockedChat(_ peerIdValue: Int64, _ locked: Bool) {
        var list = self.lockedChats.filter { $0 != String(peerIdValue) }
        if locked {
            list.append(String(peerIdValue))
        }
        self.lockedChats = list
    }
}

/// Chats unlocked with Face ID stay open until the app goes to the background.
public final class HolyGramChatLocks {
    public static let shared = HolyGramChatLocks()

    private var unlocked: Set<Int64> = []

    public func isUnlocked(_ peerIdValue: Int64) -> Bool {
        return self.unlocked.contains(peerIdValue)
    }

    public func markUnlocked(_ peerIdValue: Int64) {
        self.unlocked.insert(peerIdValue)
    }

    /// Called when the app resigns active.
    public func lockAll() {
        self.unlocked.removeAll()
    }

    /// Face ID / Touch ID, falling back to the device passcode. Calls back on the main queue.
    public static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode on the device: nothing to check against.
            DispatchQueue.main.async {
                completion(true)
            }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        })
    }
}

/// Index of messages HolyGram kept after they were deleted, newest last, for the Deleted Messages screen.
public enum HolyGramDeletedIndex {
    public struct Entry: Equatable {
        public let peerId: Int64
        public let namespace: Int32
        public let id: Int32
        public let deletedAt: Int32
    }

    private static let key = "holygram_deleted_index_v1"
    private static let limit = 3000
    private static let lock = NSLock()

    public static func add(peerId: Int64, namespace: Int32, id: Int32, deletedAt: Int32) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var list = UserDefaults.standard.stringArray(forKey: self.key) ?? []
        list.append("\(peerId):\(namespace):\(id):\(deletedAt)")
        if list.count > self.limit {
            list.removeFirst(list.count - self.limit)
        }
        UserDefaults.standard.set(list, forKey: self.key)
    }

    /// Newest first.
    public static func entries() -> [Entry] {
        self.lock.lock()
        defer { self.lock.unlock() }
        let list = UserDefaults.standard.stringArray(forKey: self.key) ?? []
        return list.reversed().compactMap { line -> Entry? in
            let parts = line.split(separator: ":")
            guard parts.count == 4, let peerId = Int64(parts[0]), let namespace = Int32(parts[1]), let id = Int32(parts[2]), let deletedAt = Int32(parts[3]) else {
                return nil
            }
            return Entry(peerId: peerId, namespace: namespace, id: id, deletedAt: deletedAt)
        }
    }

    public static func clear() {
        self.lock.lock()
        defer { self.lock.unlock() }
        UserDefaults.standard.removeObject(forKey: self.key)
    }
}

/// Messages the user bookmarked from the message menu, newest last.
public enum HolyGramBookmarks {
    private static let key = "holygram_bookmarks_v1"
    private static let lock = NSLock()

    private static func load() -> [String] {
        return UserDefaults.standard.stringArray(forKey: self.key) ?? []
    }

    private static func token(peerId: Int64, namespace: Int32, id: Int32) -> String {
        return "\(peerId):\(namespace):\(id)"
    }

    public static func contains(peerId: Int64, namespace: Int32, id: Int32) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load().contains(self.token(peerId: peerId, namespace: namespace, id: id))
    }

    public static func set(peerId: Int64, namespace: Int32, id: Int32, bookmarked: Bool) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let value = self.token(peerId: peerId, namespace: namespace, id: id)
        var list = self.load().filter { $0 != value }
        if bookmarked {
            list.append(value)
        }
        UserDefaults.standard.set(list, forKey: self.key)
    }

    /// Newest first: (peerId, namespace, id).
    public static func entries() -> [(Int64, Int32, Int32)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load().reversed().compactMap { line in
            let parts = line.split(separator: ":")
            guard parts.count == 3, let peerId = Int64(parts[0]), let namespace = Int32(parts[1]), let id = Int32(parts[2]) else {
                return nil
            }
            return (peerId, namespace, id)
        }
    }
}

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
        HolyGramShared.publishFromApp()
    }

    func isSilentChat(_ peerIdValue: Int64) -> Bool {
        if self.alwaysSilent && self.hgPro {
            return true
        }
        return self.hgPro && self.silentChats.contains(String(peerIdValue))
    }

    func setSilentChat(_ peerIdValue: Int64, _ silent: Bool) {
        var list = self.silentChats.filter { $0 != String(peerIdValue) }
        if silent {
            list.append(String(peerIdValue))
        }
        self.silentChats = list
    }

    func isLockedAccount(_ accountIdValue: Int64) -> Bool {
        return self.hgPro && self.lockedAccounts.contains(String(accountIdValue))
    }

    func setLockedAccount(_ accountIdValue: Int64, _ locked: Bool) {
        var list = self.lockedAccounts.filter { $0 != String(accountIdValue) }
        if locked {
            list.append(String(accountIdValue))
        }
        self.lockedAccounts = list
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
        HolyGramShared.publishFromApp()
    }
}

/// Chats unlocked with Face ID stay open until the app goes to the background.
public final class HolyGramChatLocks {
    public static let shared = HolyGramChatLocks()

    private var unlocked: Set<Int64> = []
    private var unlockedAccounts: Set<Int64> = []

    public func isAccountUnlocked(_ accountIdValue: Int64) -> Bool {
        return self.unlockedAccounts.contains(accountIdValue)
    }

    public func markAccountUnlocked(_ accountIdValue: Int64) {
        self.unlockedAccounts.insert(accountIdValue)
    }

    public func isUnlocked(_ peerIdValue: Int64) -> Bool {
        return self.unlocked.contains(peerIdValue)
    }

    public func markUnlocked(_ peerIdValue: Int64) {
        self.unlocked.insert(peerIdValue)
    }

    /// Called when the app resigns active.
    public func lockAll() {
        self.unlocked.removeAll()
        self.unlockedAccounts.removeAll()
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

    private static let legacyKey = "holygram_deleted_index_v1"
    private static let limit = 3000
    private static let lock = NSLock()
    private static let writeQueue = DispatchQueue(label: "holygram.deletedIndex", qos: .utility)
    // Kept in memory and written to a file in the background: a deletion no longer rewrites
    // the whole list in UserDefaults (which also woke every UserDefaults observer).
    private static var loaded: [String]?
    private static var writeScheduled = false

    private static var fileURL: URL? {
        return HolyGramShared.directory?.appendingPathComponent("holygram-deleted-index.txt")
    }

    /// Extensions append here; the app folds it into the main list when it loads.
    private static var pendingURL: URL? {
        return HolyGramShared.directory?.appendingPathComponent("holygram-deleted-index-pending.txt")
    }

    /// Must be called with `lock` held.
    private static func load() -> [String] {
        if let loaded = self.loaded {
            return loaded
        }
        var list: [String] = []
        if let url = self.fileURL, let text = try? String(contentsOf: url, encoding: .utf8) {
            list = text.split(separator: "\n").map(String.init)
        } else if let legacy = UserDefaults.standard.stringArray(forKey: self.legacyKey) {
            list = legacy
            UserDefaults.standard.removeObject(forKey: self.legacyKey)
            self.scheduleWrite()
        }
        if !HolyGramShared.isAppExtension, let pendingURL = self.pendingURL, let pending = try? String(contentsOf: pendingURL, encoding: .utf8) {
            let lines = pending.split(separator: "\n").map(String.init)
            if !lines.isEmpty {
                let known = Set(list)
                list.append(contentsOf: lines.filter { !known.contains($0) })
                if list.count > self.limit {
                    list.removeFirst(list.count - self.limit)
                }
                self.scheduleWrite()
            }
            try? FileManager.default.removeItem(at: pendingURL)
        }
        self.loaded = list
        return list
    }

    /// Picks up what the notification service kept while the app was closed.
    public static func reloadFromDisk() {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.loaded != nil {
            self.loaded = nil
            _ = self.load()
        }
    }

    /// Must be called with `lock` held.
    private static func scheduleWrite() {
        if self.writeScheduled {
            return
        }
        self.writeScheduled = true
        self.writeQueue.asyncAfter(deadline: .now() + 1.0) {
            self.lock.lock()
            self.writeScheduled = false
            let snapshot = self.loaded ?? []
            self.lock.unlock()
            guard let url = self.fileURL else {
                return
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? snapshot.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public static func add(peerId: Int64, namespace: Int32, id: Int32, deletedAt: Int32) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if HolyGramShared.isAppExtension {
            // Never rewrite the app's list from an extension: append to the pending file.
            guard let url = self.pendingURL else {
                return
            }
            let line = "\(peerId):\(namespace):\(id):\(deletedAt)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
            return
        }
        var list = self.load()
        list.append("\(peerId):\(namespace):\(id):\(deletedAt)")
        if list.count > self.limit {
            list.removeFirst(list.count - self.limit)
        }
        self.loaded = list
        self.scheduleWrite()
    }

    /// Newest first.
    public static func entries() -> [Entry] {
        self.lock.lock()
        let list = self.load()
        self.lock.unlock()
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
        self.loaded = []
        UserDefaults.standard.removeObject(forKey: self.legacyKey)
        self.scheduleWrite()
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

// MARK: HolyGram: a private note about a chat, kept on this device only
public enum HolyGramNotes {
    private static let key = "holygram_chat_notes_v1"
    private static let lock = NSLock()
    // Read on every chat list row, so it is kept in memory.
    private static var cache: [String: String]?

    /// Must be called with `lock` held.
    private static func load() -> [String: String] {
        if let cache = self.cache {
            return cache
        }
        let value = (UserDefaults.standard.dictionary(forKey: self.key) as? [String: String]) ?? [:]
        self.cache = value
        return value
    }

    public static func note(peerId: Int64) -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load()[String(peerId)]
    }

    public static var isEmpty: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load().isEmpty
    }

    /// An empty text removes the note.
    public static func setNote(peerId: Int64, text: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var notes = self.load()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[String(peerId)] = trimmed.isEmpty ? nil : trimmed
        self.cache = notes
        UserDefaults.standard.set(notes, forKey: self.key)
    }

    public static func all() -> [(peerId: Int64, text: String)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load().compactMap { key, value in
            Int64(key).map { (peerId: $0, text: value) }
        }
    }
}

// MARK: HolyGram: saved message templates, newest last
public enum HolyGramTemplates {
    private static let key = "holygram_templates_v1"
    private static let lock = NSLock()
    public static let maxCount = 50

    public static func all() -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return UserDefaults.standard.stringArray(forKey: self.key) ?? []
    }

    public static func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        var list = (UserDefaults.standard.stringArray(forKey: self.key) ?? []).filter { $0 != trimmed }
        list.append(trimmed)
        UserDefaults.standard.set(Array(list.suffix(self.maxCount)), forKey: self.key)
    }

    public static func remove(_ text: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let list = (UserDefaults.standard.stringArray(forKey: self.key) ?? []).filter { $0 != text }
        UserDefaults.standard.set(list, forKey: self.key)
    }
}

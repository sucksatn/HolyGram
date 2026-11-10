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

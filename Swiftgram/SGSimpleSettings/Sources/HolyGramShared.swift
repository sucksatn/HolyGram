// MARK: HolyGram: settings and files the app shares with its extensions
import Foundation
import SGAppGroupIdentifier
import WidgetKit

public enum HolyGramShared {
    private static let keepDeletedKey = "holygram_keep_deleted"
    private static let privateChatsKey = "holygram_private_chats"
    private static let ghostOnKey = "holygram_ghost_on"
    private static let ghostUntilKey = "holygram_ghost_until"

    /// The notification service and other extensions run in their own process with their own
    /// UserDefaults, so they read what the app published to the shared app group instead.
    public static let isAppExtension: Bool = Bundle.main.bundlePath.hasSuffix(".appex")

    private static let groupDefaults: UserDefaults? = UserDefaults(suiteName: sgAppGroupIdentifier())

    /// Whether an extension should keep deleted messages, as last published by the app.
    public static var keepDeletedInExtensions: Bool {
        return self.groupDefaults?.bool(forKey: self.keepDeletedKey) ?? false
    }

    /// Called by the app on launch and whenever it goes to the background.
    public static func publishFromApp() {
        guard !self.isAppExtension else {
            return
        }
        let settings = SGSimpleSettings.shared
        let value = settings.hgSaveDeletedMessages
        if self.groupDefaults?.bool(forKey: self.keepDeletedKey) != value {
            self.groupDefaults?.set(value, forKey: self.keepDeletedKey)
        }
        // Hidden and Face ID-locked chats: notifications from them don't show who wrote or what.
        var privateChats: [String] = []
        if settings.hgPro && settings.hidePrivateNotifications {
            privateChats = Array(Set(settings.hiddenChats + settings.lockedChats)).sorted()
        }
        if (self.groupDefaults?.stringArray(forKey: self.privateChatsKey) ?? []) != privateChats {
            self.groupDefaults?.set(privateChats, forKey: self.privateChatsKey)
        }
        // Ghost mode state for the Home Screen widget.
        let ghostOn = settings.ghostMode && !settings.ghostTimerExpired && settings.hgPro && settings.hgGhostAvailable
        let ghostUntil = ghostOn && settings.ghostUntil != 0 ? Double(settings.ghostUntil) : 0.0
        if self.groupDefaults?.object(forKey: self.ghostOnKey) as? Bool != ghostOn || self.groupDefaults?.double(forKey: self.ghostUntilKey) != ghostUntil {
            self.groupDefaults?.set(ghostOn, forKey: self.ghostOnKey)
            self.groupDefaults?.set(ghostUntil, forKey: self.ghostUntilKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "HolyGramGhostWidget")
        }
    }

    /// Read by the notification service.
    public static func isPrivateNotificationChat(_ peerIdValue: Int64) -> Bool {
        guard let list = self.groupDefaults?.stringArray(forKey: self.privateChatsKey), !list.isEmpty else {
            return false
        }
        return list.contains(String(peerIdValue))
    }

    /// The app group container when the build has one (shared with extensions), else Application Support.
    public static var directory: URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sgAppGroupIdentifier()) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}

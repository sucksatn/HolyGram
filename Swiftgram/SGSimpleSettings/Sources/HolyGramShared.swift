// MARK: HolyGram: settings and files the app shares with its extensions
import Foundation
import SGAppGroupIdentifier

public enum HolyGramShared {
    private static let keepDeletedKey = "holygram_keep_deleted"

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
        let value = SGSimpleSettings.shared.hgSaveDeletedMessages
        if self.groupDefaults?.bool(forKey: self.keepDeletedKey) != value {
            self.groupDefaults?.set(value, forKey: self.keepDeletedKey)
        }
    }

    /// The app group container when the build has one (shared with extensions), else Application Support.
    public static var directory: URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sgAppGroupIdentifier()) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}

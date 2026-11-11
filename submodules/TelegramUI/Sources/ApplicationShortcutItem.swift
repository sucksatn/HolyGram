import Foundation
import UIKit
import TelegramPresentationData
import DeviceAccess
import SGSimpleSettings // MARK: HolyGram

enum ApplicationShortcutItemType: String {
    case search
    case compose
    case camera
    case savedMessages
    case account
    case appIcon
    case holyGramGhost // MARK: HolyGram
}

struct ApplicationShortcutItem: Equatable {
    let type: ApplicationShortcutItemType
    let title: String
    let subtitle: String?
}

@available(iOS 9.1, *)
extension ApplicationShortcutItem {
    func shortcutItem() -> UIApplicationShortcutItem {
        let icon: UIApplicationShortcutIcon
        switch self.type {
            case .search:
                icon = UIApplicationShortcutIcon(type: .search)
            case .compose:
                icon = UIApplicationShortcutIcon(type: .compose)
            case .camera:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/Camera")
            case .savedMessages:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/SavedMessages")
            case .account:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/Account")
            case .appIcon:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/AppIcon")
            case .holyGramGhost:
                icon = UIApplicationShortcutIcon(systemImageName: "eye.slash")
        }
        return UIApplicationShortcutItem(type: self.type.rawValue, localizedTitle: self.title, localizedSubtitle: self.subtitle, icon: icon, userInfo: nil)
    }
}

func applicationShortcutItems(strings: PresentationStrings, otherAccountName: String?) -> [ApplicationShortcutItem] {
    // MARK: HolyGram: ghost mode switch instead of Search (search is one tap away in the app)
    let items = applicationShortcutItemsOriginal(strings: strings, otherAccountName: otherAccountName)
    let settings = SGSimpleSettings.shared
    guard settings.hgPro && settings.hgGhostAvailable && settings.ghostShortcut else {
        return items
    }
    let ru = strings.baseLanguageCode.hasPrefix("ru") || strings.baseLanguageCode.hasPrefix("uk")
    var result = items.filter { $0.type != .search }
    result.insert(ApplicationShortcutItem(type: .holyGramGhost, title: ru ? "Режим призрака" : "Ghost Mode", subtitle: ru ? "Включить или выключить" : "Turn on or off"), at: 0)
    return result
}

private func applicationShortcutItemsOriginal(strings: PresentationStrings, otherAccountName: String?) -> [ApplicationShortcutItem] {
    if let otherAccountName = otherAccountName {
        return [
            ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil),
            ApplicationShortcutItem(type: .compose, title: strings.Compose_NewMessage, subtitle: nil),
            ApplicationShortcutItem(type: .savedMessages, title: strings.Conversation_SavedMessages, subtitle: nil),
            ApplicationShortcutItem(type: .account, title: strings.Shortcut_SwitchAccount, subtitle: otherAccountName)
        ]
    } else {
        return [
            ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil),
            ApplicationShortcutItem(type: .compose, title: strings.Compose_NewMessage, subtitle: nil),
            ApplicationShortcutItem(type: .savedMessages, title: strings.Conversation_SavedMessages, subtitle: nil),
            ApplicationShortcutItem(type: .appIcon, title: strings.Shortcut_AppIcon, subtitle: nil)
        ]
    }
}

// MARK: Swiftgram
import SGLogging
import SGSimpleSettings
import SGStrings
import SGAPIToken

import SGItemListUI
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import MtProtoKit
import MessageUI
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import AccountContext
import AppBundle
import WebKit
import PeerNameColorScreen
import UndoUI
import SGProUI


private enum SGControllerSection: Int32, SGItemListSection {
    case search
    case trending
    case content
    case holyGramPro // MARK: HolyGram
    case ghost // MARK: HolyGram
    case messageHistory // MARK: HolyGram
    case holyGramPrivacy // MARK: HolyGram
    case holyGramMenus // MARK: HolyGram
    case holyGramTools // MARK: HolyGram
    case holyGramNav // MARK: HolyGram
    case tabs
    case folders
    case chatList
    case profiles
    case stories
    case translation
    case voiceMessages
    case calls
    case photo
    case stickers
    case videoNotes
    case contextMenu
    case accountColors
    case other
}

private enum SGBoolSetting: String {
    case hgShowGhostButton
    case menuGhostException
    case menuHideChat
    case menuLockChat
    case menuSilentChat
    case menuCopyId
    case menuDeleteMine
    case menuBookmark
    case menuRemind
    case menuChatStats
    case menuSaveAllMedia
    case menuEditHistory
    case menuExportChat
    case menuFirstMessage
    case menuTemplates
    case menuChatNote
    case menuMessageInfo
    case menuSpeak
    case menuCopyWithAuthor
    case menuWriteAuthor
    case menuMessageCard
    // MARK: HolyGram ghost mode
    case ghostMode
    case ghostHideOnline
    case ghostNoReadReceipts
    case ghostNoTyping
    case ghostNoStoryViews
    case ghostReadOnReply
    case saveDeletedMessages
    case saveEditHistory
    case keepSelfDestructingMedia
    case hideInAppSwitcher
    case hideSponsoredMessages
    case streamerMode
    case hidePaidFeatureRows
    case confirmStickerSend
    case confirmVoiceSend
    case hideBlockedUsersMessages
    case hideFolderBadges
    case hideSimilarChannels
    case hidePhoneInSettings
    case showTabNames
    case showContactsTab
    case showCallsTab
    case wideTabBar
    case foldersAtBottom
    case startTelescopeWithRearCam
    case hideStories
    case uploadSpeedBoost
    case showProfileId
    case warnOnStoriesOpen
    case sendWithReturnKey
    case rememberLastFolder
    case sendLargePhotos
    case storyStealthMode
    case disableSwipeToRecordStory
    case disableDeleteChatSwipeOption
    case quickTranslateButton
    case hideReactions
    case showRepostToStory
    case contextShowSelectFromUser
    case contextShowSaveToCloud
    case contextShowHideForwardName
    case contextShowRestrict
    case contextShowReport
    case contextShowReply
    case contextShowPin
    case contextShowSaveMedia
    case contextShowMessageReplies
    case contextShowJson
    case contextShowRepeat // MARK: HolyGram
    case disableScrollToNextChannel
    case disableScrollToNextTopic
    case disableChatSwipeOptions
    case disableGalleryCamera
    case disableGalleryCameraPreview
    case disableSendAsButton
    case disableSnapDeletionEffect
    case stickerTimestamp
    case hideRecordingButton
    case hideTabBar
    case showDC
    case showCreationDate
    case showRegDate
    case compactChatList
    case compactMessagePreview
    case compactFolderNames
    case allChatsHidden
    case defaultEmojisFirst
    case messageDoubleTapActionOutgoingEdit
    case wideChannelPosts
    case forceEmojiTab
    case forceBuiltInMic
    case secondsInMessages
    case hideChannelBottomButton
    case confirmCalls
    case swipeForVideoPIP
    case enableVoipTcp
    case nyStyleSnow
    case nyStyleLightning
    case tabBarSearchEnabled
    case videoControlsInFooter
    case hideAccountInNotifications
}

private enum SGOneFromManySetting: String {
    case nyStyle
    case bottomTabStyle
    case downloadSpeedBoost
    case allChatsTitleLengthOverride
//    case allChatsFolderPositionOverride
    case translationBackend
    case transcriptionBackend
}

private enum SGSliderSetting: String {
    case accountColorsSaturation
    case outgoingPhotoQuality
    case stickerSize
}

private enum SGDisclosureLink: String {
    case holyGramProContact // MARK: HolyGram
    case pageGhost // MARK: HolyGram
    case pageHistory // MARK: HolyGram
    case pagePrivacy // MARK: HolyGram
    case pageMenus // MARK: HolyGram
    case pageTools // MARK: HolyGram
    case pageSwiftgram // MARK: HolyGram
    case pageBackup // MARK: HolyGram
    case pageMorePro // MARK: HolyGram
    case holyGramNotes // MARK: HolyGram
    case holyGramTemplates // MARK: HolyGram
    case holyGramHiddenChats // MARK: HolyGram
    case holyGramDeletedMessages // MARK: HolyGram
    case holyGramBookmarks // MARK: HolyGram
    case holyGramDrafts // MARK: HolyGram
    case holyGramMentions // MARK: HolyGram
    case contentSettings
    case languageSettings
}

private struct PeerNameColorScreenState: Equatable {
    var updatedNameColor: PeerNameColor?
    var updatedBackgroundEmojiId: Int64?
}

private struct SGSettingsControllerState: Equatable {
    var searchQuery: String?
}

private typealias SGControllerEntry = SGItemListUIEntry<SGControllerSection, SGBoolSetting, SGSliderSetting, SGOneFromManySetting, SGDisclosureLink, AnyHashable>

// MARK: HolyGram: the settings are split into a hub and sub-pages
public enum HolyGramSettingsPage: String {
    case root
    case ghost
    case history
    case privacy
    case menus
    case tools
    case swiftgram

    fileprivate var sections: Set<SGControllerSection>? {
        switch self {
        case .root:
            return [.holyGramPro, .holyGramNav]
        case .ghost:
            return [.ghost]
        case .history:
            return [.messageHistory]
        case .privacy:
            return [.holyGramPrivacy]
        case .menus:
            return [.holyGramMenus]
        case .tools:
            return [.holyGramTools]
        case .swiftgram:
            return nil
        }
    }

    fileprivate func title(_ ru: Bool) -> String {
        switch self {
        case .root:
            return "HolyGram Pro"
        case .ghost:
            return ru ? "Режим призрака" : "Ghost Mode"
        case .history:
            return ru ? "История сообщений" : "Message History"
        case .privacy:
            return ru ? "Конфиденциальность" : "Privacy"
        case .menus:
            return ru ? "Меню чатов и сообщений" : "Chat & Message Menus"
        case .tools:
            return ru ? "Инструменты" : "Tools"
        case .swiftgram:
            return "HolyGram"
        }
    }
}

private let holyGramOwnSections: Set<SGControllerSection> = [.holyGramPro, .holyGramNav, .ghost, .messageHistory, .holyGramPrivacy, .holyGramMenus, .holyGramTools]

// MARK: HolyGram: the view controller to present plain UIKit alerts from
func hgTopViewController() -> UIViewController? {
    var presenter = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }.first?.rootViewController
    while let presented = presenter?.presentedViewController {
        presenter = presented
    }
    return presenter
}

// MARK: HolyGram Pro status line for the settings screen
private func holyGramProStatusText(lang: String) -> String {
    let pro = HolyGramPro.shared
    guard pro.isConfigured else {
        return i18n("Settings.HGPro.NotConfigured", lang)
    }
    let note = i18n("Settings.HGPro.DeviceNotice", lang)
    if let status = pro.status, status.isActive() {
        if status.expiresAt == -1 {
            return i18n("Settings.HGPro.ActiveForever", lang) + "\n" + note
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang)
        formatter.dateStyle = .long
        let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(status.expiresAt)))
        return i18n("Settings.HGPro.ActiveUntil", lang, date) + "\n" + note
    }
    return i18n("Settings.HGPro.Inactive", lang) + "\n" + note
}

private func SGControllerEntries(presentationData: PresentationData, callListSettings: CallListSettings, experimentalUISettings: ExperimentalUISettings, appConfiguration: AppConfiguration, nameColors: PeerNameColors, state: SGSettingsControllerState, page: HolyGramSettingsPage) -> [SGControllerEntry] {
    
    let lang = presentationData.strings.baseLanguageCode
    let strings = presentationData.strings
    let newStr = strings.Settings_New
    var entries: [SGControllerEntry] = []
    
    let id = SGItemListCounter()
    
    entries.append(.searchInput(id: id.count, section: .search, title: NSAttributedString(string: "🔍"), text: state.searchQuery ?? "", placeholder: strings.Common_Search))
    
    
    if SGSimpleSettings.shared.canUseNY {
        entries.append(.header(id: id.count, section: .trending, text: i18n("Settings.NY.Header", lang), badge: newStr))
        entries.append(.toggle(id: id.count, section: .trending, settingName: .nyStyleSnow, value: SGSimpleSettings.shared.nyStyle == SGSimpleSettings.NYStyle.snow.rawValue, text: i18n("Settings.NY.Style.snow", lang), enabled: true))
        entries.append(.toggle(id: id.count, section: .trending, settingName: .nyStyleLightning, value: SGSimpleSettings.shared.nyStyle == SGSimpleSettings.NYStyle.lightning.rawValue, text: i18n("Settings.NY.Style.lightning", lang), enabled: true))
        // entries.append(.oneFromManySelector(id: id.count, section: .trending, settingName: .nyStyle, text: i18n("Settings.NY.Style", lang), value: i18n("Settings.NY.Style.\(SGSimpleSettings.shared.nyStyle)", lang), enabled: true))
        entries.append(.notice(id: id.count, section: .trending, text: i18n("Settings.NY.Notice", lang)))
    } else {
        id.increment(3)
    }
    
    if appConfiguration.sgWebSettings.global.canEditSettings {
        entries.append(.disclosure(id: id.count, section: .content, link: .contentSettings, text: i18n("Settings.ContentSettings", lang)))
    } else {
        id.increment(1)
    }
    
    // MARK: HolyGram Pro
    let pro = HolyGramPro.shared
    let hasPro = SGSimpleSettings.shared.hgPro
    let lock = hasPro ? "" : " 🔒"
    let ru = lang.hasPrefix("ru") || lang.hasPrefix("uk")
    let settings = SGSimpleSettings.shared
    let ghostAvailable = settings.hgGhostAvailable
    entries.append(.header(id: id.count, section: .holyGramPro, text: "💎 HOLYGRAM PRO", badge: nil))
    entries.append(.notice(id: id.count, section: .holyGramPro, text: holyGramProStatusText(lang: lang)))
    entries.append(.action(id: id.count, section: .holyGramPro, actionType: AnyHashable("hgCopyDeviceCode"), text: i18n("Settings.HGPro.Device", lang, pro.displayDeviceCode), kind: .generic))
    if !HolyGramPro.botUsername.isEmpty {
        entries.append(.disclosure(id: id.count, section: .holyGramPro, link: .holyGramProContact, text: (hasPro && pro.isConfigured ? "⚙️ " : "💎 ") + i18n(hasPro && pro.isConfigured ? "Settings.HGPro.Manage" : "Settings.HGPro.Get", lang)))
    } else {
        id.increment(1)
    }

    // Hub: one row per page, with a short state
    entries.append(.header(id: id.count, section: .holyGramNav, text: ru ? "ФУНКЦИИ HOLYGRAM" : "HOLYGRAM FEATURES", badge: nil))
    if ghostAvailable {
        entries.append(.disclosure(id: id.count, section: .holyGramNav, link: .pageGhost, text: "👻  " + (ru ? "Режим призрака" : "Ghost Mode")))
    } else {
        id.increment(1)
    }
    entries.append(.disclosure(id: id.count, section: .holyGramNav, link: .pageHistory, text: "🗂  " + (ru ? "История сообщений" : "Message History")))
    entries.append(.disclosure(id: id.count, section: .holyGramNav, link: .pagePrivacy, text: "🔐  " + (ru ? "Конфиденциальность" : "Privacy")))
    entries.append(.disclosure(id: id.count, section: .holyGramNav, link: .pageMenus, text: "💬  " + (ru ? "Меню чатов и сообщений" : "Chat & Message Menus")))
    entries.append(.disclosure(id: id.count, section: .holyGramNav, link: .pageTools, text: "🧰  " + (ru ? "Инструменты" : "Tools")))
    entries.append(.disclosure(id: id.count, section: .holyGramNav, link: .pageBackup, text: "🗄  " + (ru ? "Бэкап и перенос аккаунтов" : "Account Backup & Transfer")))
    entries.append(.disclosure(id: id.count, section: .holyGramNav, link: .pageMorePro, text: "✨  " + (ru ? "Ещё: фильтр, панель ввода, значки, иконки" : "More: Filter, Input Toolbar, Badges, Icons")))
    entries.append(.notice(id: id.count, section: .holyGramNav, text: ru ? "Функции с 🔒 работают с HolyGram Pro." : "Features marked 🔒 need HolyGram Pro."))

    // 👻 Ghost mode (can be switched off for everyone from the admin bot)
    if ghostAvailable {
        let ghostOn = settings.ghostMode && hasPro
        entries.append(.header(id: id.count, section: .ghost, text: i18n("Settings.Ghost.Header", lang), badge: nil))
        entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostMode, value: ghostOn, text: "👻  " + i18n("Settings.Ghost.Enabled", lang) + lock, enabled: hasPro))
        entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostHideOnline, value: settings.ghostHideOnline, text: i18n("Settings.Ghost.HideOnline", lang), enabled: ghostOn))
        entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostNoReadReceipts, value: settings.ghostNoReadReceipts, text: i18n("Settings.Ghost.NoReadReceipts", lang), enabled: ghostOn))
        entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostReadOnReply, value: settings.ghostReadOnReply, text: i18n("Settings.Ghost.ReadOnReply", lang), enabled: ghostOn && settings.ghostNoReadReceipts))
        entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostNoTyping, value: settings.ghostNoTyping, text: i18n("Settings.Ghost.NoTyping", lang), enabled: ghostOn))
        entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostNoStoryViews, value: settings.ghostNoStoryViews, text: i18n("Settings.Ghost.NoStoryViews", lang), enabled: ghostOn))
        entries.append(.toggle(id: id.count, section: .ghost, settingName: .hgShowGhostButton, value: settings.hgShowGhostButton, text: ru ? "Кнопка-глаз над чатами" : "Eye Button Above Chats", enabled: hasPro))
        entries.append(.notice(id: id.count, section: .ghost, text: i18n("Settings.Ghost.Notice", lang) + (ru ? "\n\nИсключения: удерживайте чат в списке → «Отправлять прочтение здесь».\nБыстрые команды: holygram://sg/ghost, ghost_on, ghost_off." : "\n\nExceptions: long-press a chat → Send Read Receipts Here.\nShortcuts: holygram://sg/ghost, ghost_on, ghost_off.")))
    } else {
        id.increment(10)
    }

    // 🗂 Message history
    entries.append(.header(id: id.count, section: .messageHistory, text: i18n("Settings.MessageHistory.Header", lang), badge: nil))
    if settings.hgDeletedAvailable {
        entries.append(.toggle(id: id.count, section: .messageHistory, settingName: .saveDeletedMessages, value: settings.saveDeletedMessages && hasPro, text: "🗑  " + i18n("Settings.MessageHistory.SaveDeleted", lang) + lock, enabled: hasPro))
    } else {
        id.increment(1)
    }
    if settings.hgEditsAvailable {
        entries.append(.toggle(id: id.count, section: .messageHistory, settingName: .saveEditHistory, value: settings.saveEditHistory && hasPro, text: "✏️  " + i18n("Settings.MessageHistory.SaveEdits", lang) + lock, enabled: hasPro))
    } else {
        id.increment(1)
    }
    if settings.hgSelfDestructAvailable {
        entries.append(.toggle(id: id.count, section: .messageHistory, settingName: .keepSelfDestructingMedia, value: settings.keepSelfDestructingMedia && hasPro, text: "⏱  " + i18n("Settings.MessageHistory.KeepSelfDestructing", lang) + lock, enabled: hasPro))
    } else {
        id.increment(1)
    }
    entries.append(.notice(id: id.count, section: .messageHistory, text: i18n("Settings.MessageHistory.Notice", lang)))

    // 🔐 Privacy
    entries.append(.header(id: id.count, section: .holyGramPrivacy, text: i18n("Settings.HGPrivacy.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .streamerMode, value: settings.streamerMode && hasPro, text: "🎥  " + i18n("Settings.HGPrivacy.StreamerMode", lang) + lock, enabled: hasPro))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .hideInAppSwitcher, value: settings.hideInAppSwitcher && hasPro, text: "🌫  " + i18n("Settings.HGPrivacy.HideInAppSwitcher", lang) + lock, enabled: hasPro))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .hideSponsoredMessages, value: settings.hideSponsoredMessages && hasPro, text: "🚫  " + i18n("Settings.HGPrivacy.HideSponsored", lang) + lock, enabled: hasPro))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .hideBlockedUsersMessages, value: settings.hideBlockedUsersMessages && hasPro, text: "🙈  " + i18n("Settings.HGPrivacy.HideBlocked", lang) + lock, enabled: hasPro))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .hideSimilarChannels, value: settings.hideSimilarChannels, text: "📺  " + i18n("Settings.HGPrivacy.HideSimilarChannels", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .hidePaidFeatureRows, value: settings.hidePaidFeatureRows, text: "⭐️  " + i18n("Settings.HGPrivacy.HidePaidRows", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .hideFolderBadges, value: settings.hideFolderBadges, text: "🔢  " + i18n("Settings.Folders.HideBadges", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .confirmStickerSend, value: settings.confirmStickerSend && hasPro, text: "🧸  " + i18n("Settings.HG.ConfirmSticker", lang) + lock, enabled: hasPro))
    entries.append(.toggle(id: id.count, section: .holyGramPrivacy, settingName: .confirmVoiceSend, value: settings.confirmVoiceSend && hasPro, text: "🎙  " + i18n("Settings.HG.ConfirmVoice", lang) + lock, enabled: hasPro))
    entries.append(.notice(id: id.count, section: .holyGramPrivacy, text: i18n("Settings.HGPrivacy.Notice", lang)))

    // 💬 Which HolyGram items appear in menus
    entries.append(.header(id: id.count, section: .holyGramMenus, text: ru ? "МЕНЮ ЧАТА (ДОЛГОЕ НАЖАТИЕ НА ЧАТ)" : "CHAT MENU (LONG-PRESS A CHAT)", badge: nil))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuGhostException, value: settings.menuGhostException, text: ru ? "👁  Отправлять прочтение здесь" : "👁  Send Read Receipts Here", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuHideChat, value: settings.menuHideChat, text: ru ? "🙈  Скрыть чат" : "🙈  Hide Chat", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuLockChat, value: settings.menuLockChat, text: ru ? "🔒  Закрыть Face ID" : "🔒  Lock with Face ID", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuSilentChat, value: settings.menuSilentChat, text: ru ? "🔕  Отправлять без звука" : "🔕  Always Send Silently", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuCopyId, value: settings.menuCopyId, text: ru ? "#️⃣  Скопировать ID и ссылку" : "#️⃣  Copy ID and Link", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuDeleteMine, value: settings.menuDeleteMine, text: ru ? "🗑  Удалить все мои сообщения" : "🗑  Delete All My Messages", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuChatNote, value: settings.menuChatNote, text: ru ? "📒  Заметка о чате" : "📒  Chat Note", enabled: true))
    entries.append(.header(id: id.count, section: .holyGramMenus, text: ru ? "МЕНЮ СООБЩЕНИЯ (ДОЛГОЕ НАЖАТИЕ НА СООБЩЕНИЕ)" : "MESSAGE MENU (LONG-PRESS A MESSAGE)", badge: nil))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .contextShowRepeat, value: settings.contextShowRepeat, text: "➕  +1", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuEditHistory, value: settings.menuEditHistory, text: ru ? "✏️  История правок" : "✏️  Edit History", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuBookmark, value: settings.menuBookmark, text: ru ? "🔖  В закладки" : "🔖  Bookmark", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuRemind, value: settings.menuRemind, text: ru ? "⏰  Напомнить" : "⏰  Remind Me", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuChatStats, value: settings.menuChatStats, text: ru ? "📊  Статистика чата" : "📊  Chat Statistics", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuSaveAllMedia, value: settings.menuSaveAllMedia, text: ru ? "📥  Сохранить все фото и видео" : "📥  Save All Photos & Videos", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuTemplates, value: settings.menuTemplates, text: ru ? "🗒  Шаблоны" : "🗒  Templates", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuExportChat, value: settings.menuExportChat, text: ru ? "📤  Экспорт чата в текст" : "📤  Export Chat as Text", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuFirstMessage, value: settings.menuFirstMessage, text: ru ? "⏮  К началу чата" : "⏮  Go to First Message", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuMessageInfo, value: settings.menuMessageInfo, text: ru ? "ℹ️  Подробности" : "ℹ️  Details", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuSpeak, value: settings.menuSpeak, text: ru ? "🔊  Озвучить" : "🔊  Read Aloud", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuCopyWithAuthor, value: settings.menuCopyWithAuthor, text: ru ? "📋  Копировать с автором" : "📋  Copy with Author", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuWriteAuthor, value: settings.menuWriteAuthor, text: ru ? "✉️  Написать автору" : "✉️  Message Author", enabled: true))
    entries.append(.toggle(id: id.count, section: .holyGramMenus, settingName: .menuMessageCard, value: settings.menuMessageCard, text: ru ? "🖼  Картинка сообщения" : "🖼  Message as Image", enabled: true))
    entries.append(.notice(id: id.count, section: .holyGramMenus, text: ru ? "Выключенные пункты не показываются в меню. Функции Pro появляются в меню только с HolyGram Pro." : "Turned-off items don't appear in menus. Pro items appear only with HolyGram Pro."))

    // 🧰 Tools
    entries.append(.header(id: id.count, section: .holyGramTools, text: ru ? "ИНСТРУМЕНТЫ" : "TOOLS", badge: nil))
    entries.append(.disclosure(id: id.count, section: .holyGramTools, link: .holyGramDeletedMessages, text: "🗑  " + i18n("Settings.MessageHistory.Browse", lang) + lock))
    entries.append(.disclosure(id: id.count, section: .holyGramTools, link: .holyGramBookmarks, text: "🔖  " + i18n("Settings.MessageHistory.Bookmarks", lang) + lock))
    entries.append(.disclosure(id: id.count, section: .holyGramTools, link: .holyGramDrafts, text: "📝  " + i18n("Settings.MessageHistory.Drafts", lang)))
    entries.append(.disclosure(id: id.count, section: .holyGramTools, link: .holyGramMentions, text: "@  " + i18n("Settings.MessageHistory.Mentions", lang)))
    entries.append(.disclosure(id: id.count, section: .holyGramTools, link: .holyGramHiddenChats, text: "🙈  " + i18n("Settings.HGPrivacy.HiddenChats", lang) + (hasPro ? (settings.hiddenChats.isEmpty ? "" : " (\(settings.hiddenChats.count))") : lock)))
    let highlight = settings.highlightKeywords.joined(separator: ", ")
    entries.append(.action(id: id.count, section: .holyGramTools, actionType: AnyHashable("hgEditHighlight"), text: "🖍  " + i18n("Settings.MessageHistory.Highlight", lang) + lock + (highlight.isEmpty ? "" : ": " + highlight), kind: .generic))
    entries.append(.disclosure(id: id.count, section: .holyGramTools, link: .holyGramTemplates, text: (ru ? "🗒  Шаблоны сообщений" : "🗒  Message Templates") + lock))
    entries.append(.disclosure(id: id.count, section: .holyGramTools, link: .holyGramNotes, text: (ru ? "📒  Заметки о чатах" : "📒  Chat Notes") + lock))
    entries.append(.action(id: id.count, section: .holyGramTools, actionType: AnyHashable("hgArchiveInactive"), text: "📦  " + i18n("Settings.HGPrivacy.ArchiveInactive", lang) + lock, kind: .generic))
    entries.append(.action(id: id.count, section: .holyGramTools, actionType: AnyHashable("hgReadAll"), text: (ru ? "✅  Прочитать все чаты" : "✅  Mark All Chats as Read") + lock, kind: .generic))
    entries.append(.action(id: id.count, section: .holyGramTools, actionType: AnyHashable("hgExportData"), text: (ru ? "📤  Экспорт закладок, заметок и шаблонов" : "📤  Export Bookmarks, Notes & Templates") + lock, kind: .generic))
    entries.append(.action(id: id.count, section: .holyGramTools, actionType: AnyHashable("hgMuteChannels"), text: (ru ? "🔇  Выключить звук всех каналов" : "🔇  Mute All Channels") + lock, kind: .generic))

    entries.append(.header(id: id.count, section: .tabs, text: i18n("Settings.Tabs.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .hideTabBar, value: SGSimpleSettings.shared.hideTabBar, text: i18n("Settings.Tabs.HideTabBar", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showContactsTab, value: callListSettings.showContactsTab, text: i18n("Settings.Tabs.ShowContacts", lang), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showCallsTab, value: callListSettings.showTab, text: strings.CallSettings_TabIcon, enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showTabNames, value: SGSimpleSettings.shared.showTabNames, text: i18n("Settings.Tabs.ShowNames", lang), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .tabBarSearchEnabled, value: SGSimpleSettings.shared.tabBarSearchEnabled, text: i18n("Settings.Tabs.SearchButton", lang), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .wideTabBar, value: SGSimpleSettings.shared.wideTabBar, text: i18n("Settings.Tabs.WideTabBar", lang), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.notice(id: id.count, section: .tabs, text: i18n("Settings.Tabs.WideTabBar.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .folders, text: strings.Settings_ChatFolders.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .foldersAtBottom, value: experimentalUISettings.foldersTabAtBottom, text: i18n("Settings.Folders.BottomTab", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .allChatsHidden, value: SGSimpleSettings.shared.allChatsHidden, text: i18n("Settings.Folders.AllChatsHidden", lang, strings.ChatList_Tabs_AllChats), enabled: true))
    #if DEBUG
//    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsFolderPositionOverride, text: i18n("Settings.Folders.AllChatsPlacement", lang), value: i18n("Settings.Folders.AllChatsPlacement.\(SGSimpleSettings.shared.allChatsFolderPositionOverride)", lang), enabled: true))
    #endif
    entries.append(.toggle(id: id.count, section: .folders, settingName: .compactFolderNames, value: SGSimpleSettings.shared.compactFolderNames, text: i18n("Settings.Folders.CompactNames", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsTitleLengthOverride, text: i18n("Settings.Folders.AllChatsTitle", lang), value: i18n("Settings.Folders.AllChatsTitle.\(SGSimpleSettings.shared.allChatsTitleLengthOverride)", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .rememberLastFolder, value: SGSimpleSettings.shared.rememberLastFolder, text: i18n("Settings.Folders.RememberLast", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .folders, text: i18n("Settings.Folders.RememberLast.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .chatList, text: i18n("Settings.ChatList.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactChatList, value: SGSimpleSettings.shared.compactChatList, text: i18n("Settings.CompactChatList", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactMessagePreview, value: SGSimpleSettings.shared.chatListLines != SGSimpleSettings.ChatListLines.three.rawValue, text: i18n("Settings.CompactMessagePreview", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableChatSwipeOptions, value: !SGSimpleSettings.shared.disableChatSwipeOptions, text: i18n("Settings.ChatSwipeOptions", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableDeleteChatSwipeOption, value: !SGSimpleSettings.shared.disableDeleteChatSwipeOption, text: i18n("Settings.DeleteChatSwipeOption", lang), enabled: !SGSimpleSettings.shared.disableChatSwipeOptions))
    
    entries.append(.header(id: id.count, section: .profiles, text: i18n("Settings.Profiles.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showProfileId, value: SGSimpleSettings.shared.showProfileId, text: i18n("Settings.ShowProfileID", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showDC, value: SGSimpleSettings.shared.showDC, text: i18n("Settings.ShowDC", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showRegDate, value: SGSimpleSettings.shared.showRegDate, text: i18n("Settings.ShowRegDate", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.ShowRegDate.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showCreationDate, value: SGSimpleSettings.shared.showCreationDate, text: i18n("Settings.ShowCreationDate", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.ShowCreationDate.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .confirmCalls, value: SGSimpleSettings.shared.confirmCalls, text: i18n("Settings.CallConfirmation", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.CallConfirmation.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .stories, text: strings.AutoDownloadSettings_Stories.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .hideStories, value: SGSimpleSettings.shared.hideStories, text: i18n("Settings.Stories.Hide", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .disableSwipeToRecordStory, value: SGSimpleSettings.shared.disableSwipeToRecordStory, text: i18n("Settings.Stories.DisableSwipeToRecord", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .warnOnStoriesOpen, value: SGSimpleSettings.shared.warnOnStoriesOpen, text: i18n("Settings.Stories.WarnBeforeView", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .showRepostToStory, value: SGSimpleSettings.shared.showRepostToStoryV2, text: strings.Share_RepostToStory.replacingOccurrences(of: "\n", with: " "), enabled: true))
    if SGSimpleSettings.shared.canUseStealthMode {
        entries.append(.toggle(id: id.count, section: .stories, settingName: .storyStealthMode, value: SGSimpleSettings.shared.storyStealthMode, text: strings.Story_StealthMode_Title, enabled: true))
        entries.append(.notice(id: id.count, section: .stories, text: strings.Story_StealthMode_ControlText))
    } else {
        id.increment(2)
    }

    
    entries.append(.header(id: id.count, section: .translation, text: strings.Localization_TranslateMessages.uppercased(), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .translation, settingName: .translationBackend, text: i18n("Settings.Translation.Backend", lang), value: i18n("Settings.Translation.Backend.\(SGSimpleSettings.shared.translationBackend)", lang), enabled: true))
    if SGSimpleSettings.shared.translationBackendEnum != .gtranslate {
        entries.append(.notice(id: id.count, section: .translation, text: i18n("Settings.Translation.Backend.Notice", lang, "Settings.Translation.Backend.\(SGSimpleSettings.TranslationBackend.gtranslate.rawValue)".i18n(lang))))
    } else {
        id.increment(1)
    }
    entries.append(.toggle(id: id.count, section: .translation, settingName: .quickTranslateButton, value: SGSimpleSettings.shared.quickTranslateButton, text: i18n("Settings.Translation.QuickTranslateButton", lang), enabled: true))
    entries.append(.disclosure(id: id.count, section: .translation, link: .languageSettings, text: strings.Localization_TranslateEntireChat))
    entries.append(.notice(id: id.count, section: .translation, text: i18n("Common.NoTelegramPremiumNeeded", lang, strings.Settings_Premium)))

    entries.append(.header(id: id.count, section: .voiceMessages, text: "Settings.Transcription.Header".i18n(lang), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .voiceMessages, settingName: .transcriptionBackend, text: i18n("Settings.Transcription.Backend", lang), value: i18n("Settings.Transcription.Backend.\(SGSimpleSettings.shared.transcriptionBackend)", lang), enabled: true))
    if SGSimpleSettings.shared.transcriptionBackendEnum != .apple {
        entries.append(.notice(id: id.count, section: .voiceMessages, text: i18n("Settings.Transcription.Backend.Notice", lang, "Settings.Transcription.Backend.\(SGSimpleSettings.TranscriptionBackend.apple.rawValue)".i18n(lang))))
    } else {
        id.increment(1)
    }
    entries.append(.header(id: id.count, section: .voiceMessages, text: strings.Privacy_VoiceMessages.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .voiceMessages, settingName: .forceBuiltInMic, value: SGSimpleSettings.shared.forceBuiltInMic, text: i18n("Settings.forceBuiltInMic", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .voiceMessages, text: i18n("Settings.forceBuiltInMic.Notice", lang)))

    entries.append(.header(id: id.count, section: .calls, text: strings.Calls_TabTitle.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .calls, settingName: .enableVoipTcp, value: experimentalUISettings.enableVoipTcp, text: "Force TCP", enabled: true))
    entries.append(.notice(id: id.count, section: .calls, text: "Common.KnowWhatYouDo".i18n(lang)))
    
    entries.append(.header(id: id.count, section: .photo, text: strings.NetworkUsageSettings_MediaImageDataSection, badge: nil))
    entries.append(.header(id: id.count, section: .photo, text: strings.PhotoEditor_QualityTool.uppercased(), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .photo, settingName: .outgoingPhotoQuality, value: SGSimpleSettings.shared.outgoingPhotoQuality))
    entries.append(.notice(id: id.count, section: .photo, text: i18n("Settings.Photo.Quality.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .photo, settingName: .sendLargePhotos, value: SGSimpleSettings.shared.sendLargePhotos, text: i18n("Settings.Photo.SendLarge", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .photo, text: i18n("Settings.Photo.SendLarge.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .stickers, text: strings.StickerPacksSettings_Title.uppercased(), badge: nil))
    entries.append(.header(id: id.count, section: .stickers, text: i18n("Settings.Stickers.Size", lang), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .stickers, settingName: .stickerSize, value: SGSimpleSettings.shared.stickerSize))
    entries.append(.toggle(id: id.count, section: .stickers, settingName: .stickerTimestamp, value: SGSimpleSettings.shared.stickerTimestamp, text: i18n("Settings.Stickers.Timestamp", lang), enabled: true))
    
    
    entries.append(.header(id: id.count, section: .videoNotes, text: i18n("Settings.VideoNotes.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .videoNotes, settingName: .startTelescopeWithRearCam, value: SGSimpleSettings.shared.startTelescopeWithRearCam, text: i18n("Settings.VideoNotes.StartWithRearCam", lang), enabled: true))
    
    entries.append(.header(id: id.count, section: .contextMenu, text: i18n("Settings.ContextMenu", lang), badge: nil))
    entries.append(.notice(id: id.count, section: .contextMenu, text: i18n("Settings.ContextMenu.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSaveToCloud, value: SGSimpleSettings.shared.contextShowSaveToCloud, text: i18n("ContextMenu.SaveToCloud", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowHideForwardName, value: SGSimpleSettings.shared.contextShowHideForwardName, text: strings.Conversation_ForwardOptions_HideSendersNames, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSelectFromUser, value: SGSimpleSettings.shared.contextShowSelectFromUser, text: i18n("ContextMenu.SelectFromUser", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowRestrict, value: SGSimpleSettings.shared.contextShowRestrict, text: strings.Conversation_ContextMenuBan, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowReport, value: SGSimpleSettings.shared.contextShowReport, text: strings.Conversation_ContextMenuReport, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowReply, value: SGSimpleSettings.shared.contextShowReply, text: strings.Conversation_ContextMenuReply, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowPin, value: SGSimpleSettings.shared.contextShowPin, text: strings.Conversation_Pin, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSaveMedia, value: SGSimpleSettings.shared.contextShowSaveMedia, text: strings.Conversation_SaveToFiles, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowMessageReplies, value: SGSimpleSettings.shared.contextShowMessageReplies, text: strings.Conversation_ContextViewThread, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowJson, value: SGSimpleSettings.shared.contextShowJson, text: "JSON", enabled: true))
    /* entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowRestrict, value: SGSimpleSettings.shared.contextShowRestrict, text: strings.Conversation_ContextMenuBan)) */
    
    entries.append(.header(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Header", lang), badge: nil))
    entries.append(.header(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Saturation", lang), badge: nil))
    let accountColorSaturation = SGSimpleSettings.shared.accountColorsSaturation
    entries.append(.percentageSlider(id: id.count, section: .accountColors, settingName: .accountColorsSaturation, value: accountColorSaturation))
//    let nameColor: PeerNameColor
//    if let updatedNameColor = state.updatedNameColor {
//        nameColor = updatedNameColor
//    } else {
//        nameColor = .blue
//    }
//    let _ = nameColors.get(nameColor, dark: presentationData.theme.overallDarkAppearance)
//    entries.append(.peerColorPicker(id: entries.count, section: .other,
//        colors: nameColors,
//        currentColor: nameColor, // TODO: PeerNameColor(rawValue: <#T##Int32#>)
//        currentSaturation: accountColorSaturation
//    ))
    
    if accountColorSaturation == 0 {
        id.increment(100)
        entries.append(.peerColorDisclosurePreview(id: id.count, section: .accountColors, name: "\(strings.UserInfo_FirstNamePlaceholder) \(strings.UserInfo_LastNamePlaceholder)", color:         presentationData.theme.chat.message.incoming.accentTextColor))
    } else {
        id.increment(200)
        for index in nameColors.displayOrder.prefix(3) {
            let color: PeerNameColor = PeerNameColor(rawValue: index)
            let colors = nameColors.get(color, dark: presentationData.theme.overallDarkAppearance)
            entries.append(.peerColorDisclosurePreview(id: id.count, section: .accountColors, name: "\(strings.UserInfo_FirstNamePlaceholder) \(strings.UserInfo_LastNamePlaceholder)", color: colors.main))
        }
    }
    entries.append(.notice(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Saturation.Notice", lang)))
    
    id.increment(10000)
    entries.append(.header(id: id.count, section: .other, text: strings.Appearance_Other.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .other, settingName: .videoControlsInFooter, value: SGSimpleSettings.shared.videoControlsInFooter, text: i18n("Settings.videoControlsInFooter", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .swipeForVideoPIP, value: SGSimpleSettings.shared.videoPIPSwipeDirection == SGSimpleSettings.VideoPIPSwipeDirection.up.rawValue, text: i18n("Settings.swipeForVideoPIP", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.swipeForVideoPIP.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideChannelBottomButton, value: !SGSimpleSettings.shared.hideChannelBottomButton, text: i18n("Settings.showChannelBottomButton", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .wideChannelPosts, value: SGSimpleSettings.shared.wideChannelPosts, text: i18n("Settings.wideChannelPosts", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .secondsInMessages, value: SGSimpleSettings.shared.secondsInMessages, text: i18n("Settings.secondsInMessages", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .messageDoubleTapActionOutgoingEdit, value: SGSimpleSettings.shared.messageDoubleTapActionOutgoing == SGSimpleSettings.MessageDoubleTapAction.edit.rawValue, text: i18n("Settings.messageDoubleTapActionOutgoingEdit", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideRecordingButton, value: !SGSimpleSettings.shared.hideRecordingButton, text: i18n("Settings.RecordingButton", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableSnapDeletionEffect, value: !SGSimpleSettings.shared.disableSnapDeletionEffect, text: i18n("Settings.SnapDeletionEffect", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableSendAsButton, value: !SGSimpleSettings.shared.disableSendAsButton, text: i18n("Settings.SendAsButton", lang, strings.Conversation_SendMesageAs), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableGalleryCamera, value: !SGSimpleSettings.shared.disableGalleryCamera, text: i18n("Settings.GalleryCamera", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableGalleryCameraPreview, value: !SGSimpleSettings.shared.disableGalleryCameraPreview, text: i18n("Settings.GalleryCameraPreview", lang), enabled: !SGSimpleSettings.shared.disableGalleryCamera))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableScrollToNextChannel, value: !SGSimpleSettings.shared.disableScrollToNextChannel, text: i18n("Settings.PullToNextChannel", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableScrollToNextTopic, value: !SGSimpleSettings.shared.disableScrollToNextTopic, text: i18n("Settings.PullToNextTopic", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideReactions, value: SGSimpleSettings.shared.hideReactions, text: i18n("Settings.HideReactions", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .uploadSpeedBoost, value: SGSimpleSettings.shared.uploadSpeedBoost, text: i18n("Settings.UploadsBoost", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .other, settingName: .downloadSpeedBoost, text: i18n("Settings.DownloadsBoost", lang), value: i18n("Settings.DownloadsBoost.\(SGSimpleSettings.shared.downloadSpeedBoost)", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.DownloadsBoost.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .sendWithReturnKey, value: SGSimpleSettings.shared.sendWithReturnKey, text: i18n("Settings.SendWithReturnKey", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .forceEmojiTab, value: SGSimpleSettings.shared.forceEmojiTab, text: i18n("Settings.ForceEmojiTab", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .defaultEmojisFirst, value: SGSimpleSettings.shared.defaultEmojisFirst, text: i18n("Settings.DefaultEmojisFirst", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.DefaultEmojisFirst.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hidePhoneInSettings, value: SGSimpleSettings.shared.hidePhoneInSettings, text: i18n("Settings.HidePhoneInSettingsUI", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.HidePhoneInSettingsUI.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideAccountInNotifications, value: SGSimpleSettings.shared.hideAccountInNotifications, text: i18n("Settings.HideAccountInNotifications", lang), enabled: true))
    
    // MARK: HolyGram: keep only this page's sections
    let pageEntries = entries.filter { entry in
        guard let section = SGControllerSection(rawValue: entry.section) else {
            return false
        }
        if let sections = page.sections {
            return sections.contains(section)
        }
        return !holyGramOwnSections.contains(section)
    }
    if page != .swiftgram {
        return pageEntries
    }
    return filterSGItemListUIEntrires(entries: pageEntries, by: state.searchQuery)
}

public func sgSettingsController(context: AccountContext, page: HolyGramSettingsPage = .root/*, focusOnItemTag: Int? = nil*/) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var hgNavigationControllerImpl: (() -> NavigationController?)?
//    var getRootControllerImpl: (() -> UIViewController?)?
//    var getNavigationControllerImpl: (() -> NavigationController?)?
    var askForRestart: (() -> Void)?
    
    let initialState = SGSettingsControllerState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SGSettingsControllerState) -> SGSettingsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
//    let sliderPromise = ValuePromise(SGSimpleSettings.shared.accountColorsSaturation, ignoreRepeated: true)
//    let sliderStateValue = Atomic(value: SGSimpleSettings.shared.accountColorsSaturation)
//    let _: ((Int32) -> Int32) -> Void = { f in
//        sliderPromise.set(sliderStateValue.modify( {f($0)}))
//    }
    
    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGItemListArguments<SGBoolSetting, SGSliderSetting, SGOneFromManySetting, SGDisclosureLink, AnyHashable>(
        context: context,
        /*updatePeerColor: { color in
          updateState { state in
              var updatedState = state
              updatedState.updatedNameColor = color
              return updatedState
          }
        },*/ setBoolValue: { setting, value in
        switch setting {
        case .hidePhoneInSettings:
            SGSimpleSettings.shared.hidePhoneInSettings = value
            askForRestart?()
        case .showTabNames:
            SGSimpleSettings.shared.showTabNames = value
            askForRestart?()
        case .showContactsTab:
            let _ = (
                updateCallListSettingsInteractively(
                    accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowContactsTab(value) }
                )
            ).start()
        case .showCallsTab:
            let _ = (
                updateCallListSettingsInteractively(
                    accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowTab(value) }
                )
            ).start()
        case .tabBarSearchEnabled:
            SGSimpleSettings.shared.tabBarSearchEnabled = value
        case .wideTabBar:
            SGSimpleSettings.shared.wideTabBar = value
            askForRestart?()
        case .foldersAtBottom:
            let _ = (
                updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                        var settings = settings
                        settings.foldersTabAtBottom = value
                        return settings
                    }
                )
            ).start()
        case .startTelescopeWithRearCam:
            SGSimpleSettings.shared.startTelescopeWithRearCam = value
        case .hideStories:
            SGSimpleSettings.shared.hideStories = value
        // MARK: HolyGram ghost mode
        case .ghostMode:
            SGSimpleSettings.shared.ghostMode = value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
        case .ghostHideOnline:
            SGSimpleSettings.shared.ghostHideOnline = value
        case .ghostNoReadReceipts:
            SGSimpleSettings.shared.ghostNoReadReceipts = value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
        case .ghostNoTyping:
            SGSimpleSettings.shared.ghostNoTyping = value
        case .ghostNoStoryViews:
            SGSimpleSettings.shared.ghostNoStoryViews = value
        case .ghostReadOnReply:
            SGSimpleSettings.shared.ghostReadOnReply = value
        case .saveDeletedMessages:
            SGSimpleSettings.shared.saveDeletedMessages = value
        case .saveEditHistory:
            SGSimpleSettings.shared.saveEditHistory = value
        case .keepSelfDestructingMedia:
            SGSimpleSettings.shared.keepSelfDestructingMedia = value
        case .hideInAppSwitcher:
            SGSimpleSettings.shared.hideInAppSwitcher = value
        case .hgShowGhostButton:
            SGSimpleSettings.shared.hgShowGhostButton = value
        case .menuGhostException:
            SGSimpleSettings.shared.menuGhostException = value
        case .menuHideChat:
            SGSimpleSettings.shared.menuHideChat = value
        case .menuLockChat:
            SGSimpleSettings.shared.menuLockChat = value
        case .menuSilentChat:
            SGSimpleSettings.shared.menuSilentChat = value
        case .menuCopyId:
            SGSimpleSettings.shared.menuCopyId = value
        case .menuDeleteMine:
            SGSimpleSettings.shared.menuDeleteMine = value
        case .menuBookmark:
            SGSimpleSettings.shared.menuBookmark = value
        case .menuRemind:
            SGSimpleSettings.shared.menuRemind = value
        case .menuChatStats:
            SGSimpleSettings.shared.menuChatStats = value
        case .menuSaveAllMedia:
            SGSimpleSettings.shared.menuSaveAllMedia = value
        case .menuEditHistory:
            SGSimpleSettings.shared.menuEditHistory = value
        case .menuExportChat:
            SGSimpleSettings.shared.menuExportChat = value
        case .menuFirstMessage:
            SGSimpleSettings.shared.menuFirstMessage = value
        case .menuTemplates:
            SGSimpleSettings.shared.menuTemplates = value
        case .menuChatNote:
            SGSimpleSettings.shared.menuChatNote = value
        case .menuMessageInfo:
            SGSimpleSettings.shared.menuMessageInfo = value
        case .menuSpeak:
            SGSimpleSettings.shared.menuSpeak = value
        case .menuCopyWithAuthor:
            SGSimpleSettings.shared.menuCopyWithAuthor = value
        case .menuWriteAuthor:
            SGSimpleSettings.shared.menuWriteAuthor = value
        case .menuMessageCard:
            SGSimpleSettings.shared.menuMessageCard = value
        case .hideSponsoredMessages:
            SGSimpleSettings.shared.hideSponsoredMessages = value
        case .streamerMode:
            SGSimpleSettings.shared.streamerMode = value
            askForRestart?()
        case .hidePaidFeatureRows:
            SGSimpleSettings.shared.hidePaidFeatureRows = value
        case .confirmStickerSend:
            SGSimpleSettings.shared.confirmStickerSend = value
        case .confirmVoiceSend:
            SGSimpleSettings.shared.confirmVoiceSend = value
        case .hideBlockedUsersMessages:
            SGSimpleSettings.shared.hideBlockedUsersMessages = value
        case .hideFolderBadges:
            SGSimpleSettings.shared.hideFolderBadges = value
        case .hideSimilarChannels:
            SGSimpleSettings.shared.hideSimilarChannels = value
            askForRestart?()
        case .showProfileId:
            SGSimpleSettings.shared.showProfileId = value
        case .warnOnStoriesOpen:
            SGSimpleSettings.shared.warnOnStoriesOpen = value
        case .sendWithReturnKey:
            SGSimpleSettings.shared.sendWithReturnKey = value
        case .rememberLastFolder:
            SGSimpleSettings.shared.rememberLastFolder = value
        case .sendLargePhotos:
            SGSimpleSettings.shared.sendLargePhotos = value
        case .storyStealthMode:
            SGSimpleSettings.shared.storyStealthMode = value
        case .disableSwipeToRecordStory:
            SGSimpleSettings.shared.disableSwipeToRecordStory = value
        case .quickTranslateButton:
            SGSimpleSettings.shared.quickTranslateButton = value
        case .uploadSpeedBoost:
            SGSimpleSettings.shared.uploadSpeedBoost = value
        case .hideReactions:
            SGSimpleSettings.shared.hideReactions = value
        case .showRepostToStory:
            SGSimpleSettings.shared.showRepostToStoryV2 = value
        case .contextShowSelectFromUser:
            SGSimpleSettings.shared.contextShowSelectFromUser = value
        case .contextShowSaveToCloud:
            SGSimpleSettings.shared.contextShowSaveToCloud = value
        case .contextShowRestrict:
            SGSimpleSettings.shared.contextShowRestrict = value
        case .contextShowHideForwardName:
            SGSimpleSettings.shared.contextShowHideForwardName = value
        case .disableScrollToNextChannel:
            SGSimpleSettings.shared.disableScrollToNextChannel = !value
        case .disableScrollToNextTopic:
            SGSimpleSettings.shared.disableScrollToNextTopic = !value
        case .disableChatSwipeOptions:
            SGSimpleSettings.shared.disableChatSwipeOptions = !value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
            askForRestart?()
        case .disableDeleteChatSwipeOption:
            SGSimpleSettings.shared.disableDeleteChatSwipeOption = !value
            askForRestart?()
        case .disableGalleryCamera:
            SGSimpleSettings.shared.disableGalleryCamera = !value
            simplePromise.set(true)
        case .disableGalleryCameraPreview:
            SGSimpleSettings.shared.disableGalleryCameraPreview = !value
        case .disableSendAsButton:
            SGSimpleSettings.shared.disableSendAsButton = !value
        case .disableSnapDeletionEffect:
            SGSimpleSettings.shared.disableSnapDeletionEffect = !value
        case .contextShowReport:
            SGSimpleSettings.shared.contextShowReport = value
        case .contextShowReply:
            SGSimpleSettings.shared.contextShowReply = value
        case .contextShowPin:
            SGSimpleSettings.shared.contextShowPin = value
        case .contextShowSaveMedia:
            SGSimpleSettings.shared.contextShowSaveMedia = value
        case .contextShowMessageReplies:
            SGSimpleSettings.shared.contextShowMessageReplies = value
        case .stickerTimestamp:
            SGSimpleSettings.shared.stickerTimestamp = value
        case .contextShowJson:
            SGSimpleSettings.shared.contextShowJson = value
        case .contextShowRepeat:
            SGSimpleSettings.shared.contextShowRepeat = value
        case .hideRecordingButton:
            SGSimpleSettings.shared.hideRecordingButton = !value
        case .hideTabBar:
            SGSimpleSettings.shared.hideTabBar = value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
            askForRestart?()
        case .showDC:
            SGSimpleSettings.shared.showDC = value
        case .showCreationDate:
            SGSimpleSettings.shared.showCreationDate = value
        case .showRegDate:
            SGSimpleSettings.shared.showRegDate = value
        case .compactChatList:
            SGSimpleSettings.shared.compactChatList = value
            askForRestart?()
        case .compactMessagePreview:
            SGSimpleSettings.shared.chatListLines = value ? SGSimpleSettings.ChatListLines.one.rawValue : SGSimpleSettings.ChatListLines.three.rawValue
            askForRestart?()
        case .compactFolderNames:
            SGSimpleSettings.shared.compactFolderNames = value
            askForRestart?()
        case .allChatsHidden:
            SGSimpleSettings.shared.allChatsHidden = value
            askForRestart?()
        case .defaultEmojisFirst:
            SGSimpleSettings.shared.defaultEmojisFirst = value
        case .messageDoubleTapActionOutgoingEdit:
            SGSimpleSettings.shared.messageDoubleTapActionOutgoing = value ? SGSimpleSettings.MessageDoubleTapAction.edit.rawValue : SGSimpleSettings.MessageDoubleTapAction.default.rawValue
        case .wideChannelPosts:
            SGSimpleSettings.shared.wideChannelPosts = value
        case .forceEmojiTab:
            SGSimpleSettings.shared.forceEmojiTab = value
        case .forceBuiltInMic:
            SGSimpleSettings.shared.forceBuiltInMic = value
        case .hideChannelBottomButton:
            SGSimpleSettings.shared.hideChannelBottomButton = !value
        case .secondsInMessages:
            SGSimpleSettings.shared.secondsInMessages = value
        case .confirmCalls:
            SGSimpleSettings.shared.confirmCalls = value
        case .swipeForVideoPIP:
            SGSimpleSettings.shared.videoPIPSwipeDirection = value ? SGSimpleSettings.VideoPIPSwipeDirection.up.rawValue : SGSimpleSettings.VideoPIPSwipeDirection.none.rawValue
        case .enableVoipTcp:
            let _ = (
                updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                        var settings = settings
                        settings.enableVoipTcp = value
                        return settings
                    }
                )
            ).start()
        case .nyStyleSnow:
            SGSimpleSettings.shared.nyStyle = value ? SGSimpleSettings.NYStyle.snow.rawValue : SGSimpleSettings.NYStyle.default.rawValue
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
        case .nyStyleLightning:
            SGSimpleSettings.shared.nyStyle = value ? SGSimpleSettings.NYStyle.lightning.rawValue : SGSimpleSettings.NYStyle.default.rawValue
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
        case .videoControlsInFooter:
            SGSimpleSettings.shared.videoControlsInFooter = value
        case .hideAccountInNotifications:
            SGSimpleSettings.shared.hideAccountInNotifications = value
            SGSimpleSettings.shared.synchronizeShared()
        }
    }, updateSliderValue: { setting, value in
        switch (setting) {
            case .accountColorsSaturation:
                if SGSimpleSettings.shared.accountColorsSaturation != value {
                    SGSimpleSettings.shared.accountColorsSaturation = value
                    simplePromise.set(true)
                }
            case .outgoingPhotoQuality:
                if SGSimpleSettings.shared.outgoingPhotoQuality != value {
                    SGSimpleSettings.shared.outgoingPhotoQuality = value
                    simplePromise.set(true)
                }
            case .stickerSize:
                if SGSimpleSettings.shared.stickerSize != value {
                    SGSimpleSettings.shared.stickerSize = value
                    simplePromise.set(true)
                }
        }

    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        switch (setting) {
            case .downloadSpeedBoost:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.downloadSpeedBoost = value
                    
                    let enableDownloadX: Bool
                    switch (value) {
                        case SGSimpleSettings.DownloadSpeedBoostValues.none.rawValue:
                            enableDownloadX = false
                        default:
                            enableDownloadX = true
                    }
                    
                    // Updating controller
                    simplePromise.set(true)

                    let _ = updateNetworkSettingsInteractively(postbox: context.account.postbox, network: context.account.network, { settings in
                        var settings = settings
                        settings.useExperimentalDownload = enableDownloadX
                        return settings
                    }).start(completed: {
                        Queue.mainQueue().async {
                            askForRestart?()
                        }
                    })
                }

                for value in SGSimpleSettings.DownloadSpeedBoostValues.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.DownloadsBoost.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .bottomTabStyle:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.bottomTabStyle = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.BottomTabStyleValues.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Folders.BottomTabStyle.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .allChatsTitleLengthOverride:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.allChatsTitleLengthOverride = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.AllChatsTitleLengthOverride.allCases {
                    let title: String
                    switch (value) {
                        case SGSimpleSettings.AllChatsTitleLengthOverride.short:
                            title = "\"\(presentationData.strings.ChatList_Tabs_All)\""
                        case SGSimpleSettings.AllChatsTitleLengthOverride.long:
                            title = "\"\(presentationData.strings.ChatList_Tabs_AllChats)\""
                        default:
                            title = i18n("Settings.Folders.AllChatsTitle.none", presentationData.strings.baseLanguageCode)
                    }
                    items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
//        case .allChatsFolderPositionOverride:
//            let setAction: (String) -> Void = { value in
//                SGSimpleSettings.shared.allChatsFolderPositionOverride = value
//                simplePromise.set(true)
//            }
//
//            for value in SGSimpleSettings.AllChatsFolderPositionOverride.allCases {
//                items.append(ActionSheetButtonItem(title: i18n("Settings.Folders.AllChatsTitle.\(value)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
//                    actionSheet?.dismissAnimated()
//                    setAction(value.rawValue)
//                }))
//            }
            case .translationBackend:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.translationBackend = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.TranslationBackend.allCases {
                    if value == .system {
                        if #available(iOS 18.0, *) {
                        } else {
                            continue // System translation is not available on iOS 17 and below
                        }
                    }
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Translation.Backend.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .transcriptionBackend:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.transcriptionBackend = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.TranscriptionBackend.allCases {
                    if #available(iOS 13.0, *) {
                    } else {
                        if value == .apple {
                            continue // Apple recognition is not available on iOS 12
                        }
                    }
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Transcription.Backend.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .nyStyle:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.nyStyle = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.NYStyle.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.NY.Style.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
        }
        
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { [weak context] link in
        guard let context else {
            return
        }
        switch (link) {
            case .holyGramMentions:
                pushControllerImpl?(holyGramMentionsController(context: context))
            case .holyGramDrafts:
                pushControllerImpl?(holyGramDraftsController(context: context))
            case .holyGramBookmarks:
                guard SGSimpleSettings.shared.hgPro else {
                    return
                }
                pushControllerImpl?(holyGramBookmarksController(context: context))
            case .holyGramDeletedMessages:
                guard SGSimpleSettings.shared.hgPro else {
                    return
                }
                pushControllerImpl?(holyGramDeletedMessagesController(context: context))
            case .holyGramHiddenChats:
                guard SGSimpleSettings.shared.hgPro else {
                    return
                }
                let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
                HolyGramChatLocks.authenticate(reason: ru ? "Показать скрытые чаты" : "Show hidden chats", completion: { [weak context] success in
                    guard success, let context else {
                        return
                    }
                    pushControllerImpl?(holyGramHiddenChatsController(context: context))
                })
            case .holyGramNotes:
                pushControllerImpl?(holyGramNotesController(context: context))
            case .holyGramTemplates:
                pushControllerImpl?(holyGramTemplatesController(context: context))
            case .pageGhost:
                pushControllerImpl?(sgSettingsController(context: context, page: .ghost))
            case .pageHistory:
                pushControllerImpl?(sgSettingsController(context: context, page: .history))
            case .pagePrivacy:
                pushControllerImpl?(sgSettingsController(context: context, page: .privacy))
            case .pageMenus:
                pushControllerImpl?(sgSettingsController(context: context, page: .menus))
            case .pageTools:
                pushControllerImpl?(sgSettingsController(context: context, page: .tools))
            case .pageSwiftgram:
                pushControllerImpl?(sgSettingsController(context: context, page: .swiftgram))
            case .pageBackup:
                pushControllerImpl?(sgSessionBackupManagerController(context: context))
            case .pageMorePro:
                pushControllerImpl?(sgProController(context: context))
            case .holyGramProContact:
                // Open the bot inside the app, not in the browser
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: HolyGramPro.shared.botRequestUrl, forceExternal: false, presentationData: presentationData, navigationController: hgNavigationControllerImpl?(), dismissInput: {})
            case .languageSettings:
                pushControllerImpl?(context.sharedContext.makeLocalizationListController(context: context))
            case .contentSettings:
                let _ = (getSGSettingsURL(context: context) |> deliverOnMainQueue).start(next: { [weak context] url in
                    guard let strongContext = context else {
                        return
                    }
                    strongContext.sharedContext.applicationBindings.openUrl(url)
                })
        }
    }, action: { [weak context] actionType in
        guard let context else {
            return
        }
        // MARK: HolyGram: words highlighted in messages, edited as a comma-separated list
        if actionType == AnyHashable("hgEditHighlight") {
            guard SGSimpleSettings.shared.hgPro else {
                return
            }
            let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
            let ru = lang.hasPrefix("ru") || lang.hasPrefix("uk")
            let alert = UIAlertController(title: ru ? "Подсветка слов" : "Highlighted Words", message: ru ? "Слова через запятую, например ваше имя. Они выделятся в сообщениях во всех чатах." : "Comma-separated words, e.g. your name. They're highlighted in messages in every chat.", preferredStyle: .alert)
            alert.addTextField { field in
                field.text = SGSimpleSettings.shared.highlightKeywords.joined(separator: ", ")
                field.placeholder = ru ? "Имя, ник, слово" : "Name, nickname, word"
                field.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: ru ? "Сохранить" : "Save", style: .default, handler: { [weak alert] _ in
                let text = alert?.textFields?.first?.text ?? ""
                SGSimpleSettings.shared.highlightKeywords = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                simplePromise.set(true)
            }))
            hgTopViewController()?.present(alert, animated: true)
            return
        }
        // MARK: HolyGram: bookmarks, chat notes and templates as one text file
        if actionType == AnyHashable("hgExportData") {
            let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
            let ru = lang.hasPrefix("ru") || lang.hasPrefix("uk")
            guard SGSimpleSettings.shared.hgPro else {
                return
            }
            let notes = HolyGramNotes.all()
            let bookmarks = HolyGramBookmarks.entries()
            let noteIds = notes.map { EnginePeer.Id($0.peerId) }
            let bookmarkIds = bookmarks.map { EngineMessage.Id(peerId: EnginePeer.Id($0.0), namespace: $0.1, id: $0.2) }
            let _ = (combineLatest(
                context.engine.data.get(EngineDataMap(noteIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init))),
                context.engine.data.get(EngineDataMap(bookmarkIds.map(TelegramEngine.EngineData.Item.Messages.Message.init)))
            )
            |> deliverOnMainQueue).start(next: { peers, messages in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM.yyyy HH:mm"
                var lines: [String] = []
                lines.append(ru ? "== Закладки ==" : "== Bookmarks ==")
                for id in bookmarkIds {
                    guard let message = messages[id] ?? nil else {
                        continue
                    }
                    let chat = message.peers[message.id.peerId].flatMap { EnginePeer($0).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) } ?? ""
                    let author = message.author?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? ""
                    let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
                    lines.append("[\(date)] \(chat)\(author.isEmpty || author == chat ? "" : " · " + author): \(message.text)")
                }
                lines.append("")
                lines.append(ru ? "== Заметки о чатах ==" : "== Chat notes ==")
                for note in notes {
                    let title = (peers[EnginePeer.Id(note.peerId)] ?? nil)?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? "ID \(note.peerId)"
                    lines.append("\(title): \(note.text)")
                }
                lines.append("")
                lines.append(ru ? "== Шаблоны ==" : "== Templates ==")
                for template in HolyGramTemplates.all() {
                    lines.append("- " + template.replacingOccurrences(of: "\n", with: "\n  "))
                }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("HolyGram-export.txt")
                do {
                    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    return
                }
                guard let presenter = hgTopViewController() else {
                    return
                }
                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1.0, height: 1.0)
                    popover.permittedArrowDirections = []
                }
                presenter.present(activity, animated: true)
            })
            return
        }
        // MARK: HolyGram: mark every chat read, or mute every channel
        if actionType == AnyHashable("hgReadAll") || actionType == AnyHashable("hgMuteChannels") {
            let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
            let ru = lang.hasPrefix("ru") || lang.hasPrefix("uk")
            guard SGSimpleSettings.shared.hgPro else {
                let alert = UIAlertController(title: nil, message: ru ? "Эта функция работает с HolyGram Pro." : "This needs HolyGram Pro.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                hgTopViewController()?.present(alert, animated: true)
                return
            }
            if actionType == AnyHashable("hgReadAll") {
                let note = SGSimpleSettings.shared.ghostBlocksReadReceipts ? (ru ? "\n\nРежим призрака включён: собеседники не увидят, что вы прочитали." : "\n\nGhost mode is on: nobody will see that you read them.") : ""
                let alert = UIAlertController(title: ru ? "Прочитать все чаты?" : "Mark all chats as read?", message: (ru ? "Все непрочитанные чаты, включая архив, будут отмечены прочитанными." : "Every unread chat, the archive included, will be marked as read.") + note, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: ru ? "Прочитать" : "Mark as Read", style: .default, handler: { _ in
                    let _ = context.engine.messages.markAllChatsAsReadInteractively(items: [(groupId: .root, filterPredicate: nil), (groupId: .archive, filterPredicate: nil)]).start()
                }))
                hgTopViewController()?.present(alert, animated: true)
                return
            }
            let _ = (context.engine.messages.chatList(group: .root, count: 3000)
            |> take(1)
            |> deliverOnMainQueue).start(next: { list in
                let peerIds = list.items.compactMap { item -> EnginePeer.Id? in
                    guard case let .channel(channel)? = item.renderedPeer.peer, case .broadcast = channel.info, !item.isMuted else {
                        return nil
                    }
                    return channel.id
                }
                let alert: UIAlertController
                if peerIds.isEmpty {
                    alert = UIAlertController(title: nil, message: ru ? "Все каналы уже без звука." : "All channels are already muted.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                } else {
                    alert = UIAlertController(title: ru ? "Выключить звук каналов?" : "Mute channels?", message: ru ? "Каналов со звуком: \(peerIds.count). Уведомления от них будут выключены навсегда." : "\(peerIds.count) channels aren't muted. They'll be muted forever.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
                    alert.addAction(UIAlertAction(title: ru ? "Выключить" : "Mute", style: .default, handler: { _ in
                        for peerId in peerIds {
                            let _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: nil, muteInterval: Int32.max).start()
                        }
                    }))
                }
                hgTopViewController()?.present(alert, animated: true)
            })
            return
        }
        // MARK: HolyGram: archive channels without posts for 30 days
        if actionType == AnyHashable("hgArchiveInactive") {
            guard SGSimpleSettings.shared.hgPro else {
                return
            }
            let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
            let ru = lang.hasPrefix("ru") || lang.hasPrefix("uk")
            let _ = (context.engine.messages.chatList(group: .root, count: 3000)
            |> take(1)
            |> deliverOnMainQueue).start(next: { list in
                let cutoff = Int32(Date().timeIntervalSince1970) - 30 * 86400
                let peerIds = list.items.compactMap { item -> EnginePeer.Id? in
                    guard case let .chatList(index) = item.index, index.pinningIndex == nil, case let .channel(channel)? = item.renderedPeer.peer, case .broadcast = channel.info, index.messageIndex.timestamp < cutoff else {
                        return nil
                    }
                    return channel.id
                }
                let alert: UIAlertController
                if peerIds.isEmpty {
                    alert = UIAlertController(title: nil, message: ru ? "Нет каналов без новых постов за 30 дней." : "No channels without posts in the last 30 days.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                } else {
                    alert = UIAlertController(title: ru ? "Архивировать каналы?" : "Archive channels?", message: ru ? "Каналов без новых постов за 30 дней: \(peerIds.count). Они переедут в архив (закреплённые не трогаются)." : "\(peerIds.count) channels have had no posts for 30 days. They'll move to the archive (pinned ones stay).", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
                    alert.addAction(UIAlertAction(title: ru ? "Архивировать" : "Archive", style: .default, handler: { _ in
                        let _ = context.engine.peers.updatePeersGroupIdInteractively(peerIds: peerIds, groupId: .archive).start()
                    }))
                }
                hgTopViewController()?.present(alert, animated: true)
            })
            return
        }
        // MARK: HolyGram: tap on the device code copies it
        guard actionType == AnyHashable("hgCopyDeviceCode") else {
            return
        }
        UIPasteboard.general.string = HolyGramPro.shared.displayDeviceCode
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .copy(text: i18n("Settings.HGPro.DeviceCopied", presentationData.strings.baseLanguageCode)), elevatedLayout: false, action: { _ in return false }), nil)
    }, searchInput: { searchQuery in
        updateState { state in
            var updatedState = state
            updatedState.searchQuery = searchQuery
            return updatedState
        }
    })
    
    let sharedData = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])
    let preferences = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.App())
    let updatedContentSettingsConfiguration = contentSettingsConfiguration(network: context.account.network)
    |> map(Optional.init)
    let contentSettingsConfiguration = Promise<ContentSettingsConfiguration?>()
    contentSettingsConfiguration.set(.single(nil)
    |> then(updatedContentSettingsConfiguration))
    
    // MARK: HolyGram Pro: refresh the status now and redraw when it changes
    HolyGramPro.shared.refresh(force: true)
    let holyGramProChanges = Signal<Void, NoError> { subscriber in
        subscriber.putNext(Void())
        let observer = NotificationCenter.default.addObserver(forName: HolyGramPro.didChangeNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(Void())
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    let combinedSimplePromise = combineLatest(simplePromise.get(), holyGramProChanges) |> map { value, _ in value }
    
    let signal = combineLatest(combinedSimplePromise, /*sliderPromise.get(),*/ statePromise.get(), context.sharedContext.presentationData, sharedData, preferences, contentSettingsConfiguration.get(),
        context.engine.accountData.observeAvailableColorOptions(scope: .replies),
        context.engine.accountData.observeAvailableColorOptions(scope: .profile)
    )
    |> map { _, /*sliderValue,*/ state, presentationData, sharedData, appConfiguration, contentSettingsConfiguration, availableReplyColors, availableProfileColors ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let callListSettings: CallListSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? CallListSettings.defaultSettings
        let experimentalUISettings: ExperimentalUISettings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
        
        let entries = SGControllerEntries(presentationData: presentationData, callListSettings: callListSettings, experimentalUISettings: experimentalUISettings, appConfiguration: appConfiguration, nameColors: PeerNameColors.with(availableReplyColors: availableReplyColors, availableProfileColors: availableProfileColors), state: state, page: page)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(page.title(presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk"))), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        // TODO(swiftgram): focusOnItemTag support
        /* var index = 0
        var scrollToItem: ListViewScrollToItem?
         if let focusOnItemTag = focusOnItemTag {
            for entry in entries {
                if entry.tag?.isEqual(to: focusOnItemTag) ?? false {
                    scrollToItem = ListViewScrollToItem(index: index, position: .top(0.0), animated: false, curve: .Default(duration: 0.0), directionHint: .Up)
                }
                index += 1
            }
        } */
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: nil /* scrollToItem*/ )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    hgNavigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
//    getRootControllerImpl = { [weak controller] in
//        return controller?.view.window?.rootViewController
//    }
//    getNavigationControllerImpl = { [weak controller] in
//        return controller?.navigationController as? NavigationController
//    }
    askForRestart = { [weak context] in
        guard let context = context else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(
            UndoOverlayController(
                presentationData: presentationData, 
                content: .info(title: nil, // i18n("Common.RestartRequired", presentationData.strings.baseLanguageCode),
                    text: i18n("Common.RestartRequired", presentationData.strings.baseLanguageCode),
                    timeout: nil,
                    customUndoText: i18n("Common.RestartNow", presentationData.strings.baseLanguageCode) //presentationData.strings.Common_Yes
                ),
                elevatedLayout: false,
                action: { action in if action == .undo { exit(0) }; return true }
            ),
            nil
        )
    }
    return controller

}

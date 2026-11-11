import SGDebugUI
import SGSettingsUI
import SGStrings
import UndoUI
//
import AccountContext
import ContactListUI
import ContextUI
import Display
import Foundation
import OverlayStatusController
import Postbox
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit
import UserNotifications
import AVFoundation
import NaturalLanguage
import CoreImage
import UniformTypeIdentifiers
import SaveToCameraRoll
import SGSimpleSettings
import ChatControllerInteraction
import ChatPresentationInterfaceState

func sgHandleInternalUrlRoute(context: AccountContext, parsedUrl: URL, navigationController: NavigationController?) -> Bool {
    guard let path = parsedUrl.pathComponents.last else {
        return false
    }
    switch path {
    // MARK: HolyGram: holygram://sg/ghost, ghost_on, ghost_off — for Shortcuts and Siri
    case "ghost", "ghost_on", "ghost_off":
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
        let text: String
        if !SGSimpleSettings.shared.hgPro {
            text = ru ? "Режим призрака доступен в HolyGram Pro" : "Ghost mode needs HolyGram Pro"
        } else {
            let enabled = path == "ghost" ? !SGSimpleSettings.shared.ghostMode : path == "ghost_on"
            SGSimpleSettings.shared.ghostMode = enabled
            SGSimpleSettings.shared.ghostUntil = 0
            HolyGramShared.publishFromApp()
            text = enabled ? (ru ? "Режим призрака включён" : "Ghost mode is on") : (ru ? "Режим призрака выключен" : "Ghost mode is off")
        }
        context.sharedContext.presentGlobalController(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: 2.5, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
        return true
    case "debug":
        if let debugController = context.sharedContext.makeDebugSettingsController(context: context) {
            navigationController?.pushViewController(debugController)
            return true
        }
    case "sgdebug", "sg_debug":
        navigationController?.pushViewController(sgDebugController(context: context))
        return true
    case "settings":
        navigationController?.pushViewController(sgSettingsController(context: context, page: .swiftgram))
        return true
    case "ios_settings":
        context.sharedContext.applicationBindings.openSettings()
        return true
    case "contacts":
        if let lastViewController = navigationController?.viewControllers.last as? ViewController {
            lastViewController.present(ContactsController(context: context), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }
        return true
    case "pro", "premium", "buy":
        if context.sharedContext.immediateSGStatus.status > 1 {
            navigationController?.pushViewController(context.sharedContext.makeSGProController(context: context))
        } else if let lastViewController = navigationController?.viewControllers.last as? ViewController {
            if let payWallController = context.sharedContext.makeSGPayWallController(context: context) {
                lastViewController.present(payWallController, in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            } else {
                lastViewController.present(context.sharedContext.makeSGUpdateIOSController(), animated: true)
            }
        }
    case "restart":
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        context.sharedContext.presentGlobalController(
            UndoOverlayController(
                presentationData: presentationData,
                content: .info(title: nil, text: "Common.RestartRequired".i18n(lang), timeout: nil, customUndoText: "Common.RestartNow".i18n(lang)),
                elevatedLayout: false,
                action: { action in if action == .undo { exit(0) }; return true }
            ),
            nil
        )
    case "restore_purchases", "pro_restore", "validate", "restore":
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        context.sharedContext.presentGlobalController(
            UndoOverlayController(
                presentationData: presentationData,
                content: .info(title: nil, text: "PayWall.Button.Restoring".i18n(lang), timeout: nil, customUndoText: nil),
                elevatedLayout: false,
                action: { _ in return false }
            ),
            nil
        )
        context.sharedContext.SGIAP?.restorePurchases {}
    default:
        break
    }
    return false
}

func sgCanRevealContent(messages: [EngineRawMessage], context: AccountContext, copyProtectionEnabled: Bool) -> Bool {
    guard !copyProtectionEnabled else {
        return false
    }
    for message in messages {
        if message.canRevealContent(contentSettings: context.currentContentSettings.with { $0 }) {
            return true
        }
    }
    return false
}

enum SGContextMenuActionFactory {
    case json(controllerInteraction: ChatControllerInteraction, context: AccountContext)
    case saveToCloud(interfaceInteraction: ChatPanelInterfaceInteraction, selectAll: Bool, isImage: Bool, messages: [EngineRawMessage])
    case hideForwardName(interfaceInteraction: ChatPanelInterfaceInteraction, selectAll: Bool, isImage: Bool, messages: [EngineRawMessage])
    case editHistory(controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case repeatMessage(context: AccountContext) // MARK: HolyGram
    case bookmark(context: AccountContext) // MARK: HolyGram
    case chatStats(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case saveAllMedia(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case remind(controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case templates(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case exportChat(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case firstMessage(controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case messageInfo(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case speak // MARK: HolyGram
    case saveFile(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case qrCode(controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case fixLayout(controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case addToNote(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case copyPlain(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case scheduleRepeat(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case links(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case webSearch(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case copyWithAuthor(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case writeToAuthor(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
    case messageCard(context: AccountContext, controllerInteraction: ChatControllerInteraction) // MARK: HolyGram
}

func sgMakeContextMenuAction(_ action: SGContextMenuActionFactory, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage) -> ContextMenuItem {
    switch action {
    case let .json(controllerInteraction, context):
        return .action(ContextMenuActionItem(text: "JSON", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Settings"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            showMessageJson(controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, message: message, context: context)
            f(.default)
        }))
    case let .saveToCloud(interfaceInteraction, selectAll, isImage, messages):
        return .action(ContextMenuActionItem(text: i18n("ContextMenu.SaveToCloud", chatPresentationInterfaceState.strings.baseLanguageCode), icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Fave"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            interfaceInteraction.forwardMessages(selectAll || isImage ? messages : [message], "forwardMessagesToCloud")
            f(.dismissWithoutContent)
        }))
    case let .hideForwardName(interfaceInteraction, selectAll, isImage, messages):
        return .action(ContextMenuActionItem(text: chatPresentationInterfaceState.strings.NotificationSettings_Stories_CompactHideName, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Forward"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            interfaceInteraction.forwardMessages(selectAll || isImage ? messages : [message], "forwardMessagesWithNoNames")
            f(.dismissWithoutContent)
        }))
    // MARK: HolyGram
    case let .repeatMessage(context):
        return .action(ContextMenuActionItem(text: "+1", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Repeat") ?? UIImage(bundleImageName: "Chat/Context Menu/Forward"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            let _ = enqueueMessages(account: context.account, peerId: message.id.peerId, messages: [
                .forward(source: message.id, threadId: message.threadId, grouping: .auto, attributes: [ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)], correlationId: nil)
            ]).startStandalone()
        }))
    case let .chatStats(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Статистика чата" : "Chat Statistics", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "chart.bar"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            hgShowChatStatistics(context: context, controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, peerId: message.id.peerId, ru: ru)
        }))
    case let .saveAllMedia(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Сохранить все фото и видео чата" : "Save All Chat Photos & Videos", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "square.and.arrow.down.on.square"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgSaveAllChatMedia(context: context, controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, peerId: message.id.peerId, ru: ru)
            }
        }))
    case .bookmark:
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        let isBookmarked = HolyGramBookmarks.contains(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id)
        return .action(ContextMenuActionItem(text: isBookmarked ? (ru ? "Убрать из закладок" : "Remove Bookmark") : (ru ? "В закладки" : "Bookmark"), icon: { theme in
            return generateTintedImage(image: UIImage(systemName: isBookmarked ? "bookmark.slash" : "bookmark"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            HolyGramBookmarks.set(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id, bookmarked: !isBookmarked)
            f(.default)
        }))
    case let .remind(controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Напомнить" : "Remind Me", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "bell"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgPresentReminderOptions(controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, message: message, ru: ru)
            }
        }))
    case let .templates(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Шаблоны" : "Templates", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "text.badge.plus"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgPresentTemplates(context: context, controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, message: message, ru: ru)
            }
        }))
    case let .exportChat(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Экспорт чата в текст" : "Export Chat as Text", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "doc.text"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgExportChatText(context: context, controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, peerId: message.id.peerId, ru: ru)
            }
        }))
    case let .messageInfo(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Подробности" : "Details", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "info.circle"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgShowMessageInfo(context: context, controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, message: message, ru: ru)
            }
        }))
    case let .links(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Ссылки из сообщения" : "Links in Message", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "link"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgPresentLinks(context: context, controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, message: message, ru: ru)
            }
        }))
    case let .webSearch(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Найти в интернете" : "Search the Web", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "globe"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            let query = String(message.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            guard !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: "https://www.google.com/search?q=\(encoded)", forceExternal: false, presentationData: presentationData, navigationController: controllerInteraction.navigationController(), dismissInput: {})
        }))
    case let .scheduleRepeat(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Отправить ещё раз позже" : "Send Again Later", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "calendar.badge.clock"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgPresentScheduleRepeat(context: context, controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, message: message, ru: ru)
            }
        }))
    case let .saveFile(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Сохранить файл" : "Save File", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "square.and.arrow.down"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            hgShareMessageFile(context: context, controllerInteraction: controllerInteraction, message: message, ru: ru)
        }))
    case let .qrCode(controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "QR-код" : "QR Code", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "qrcode"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgShareQrCode(controllerInteraction: controllerInteraction, message: message, ru: ru)
            }
        }))
    case let .fixLayout(controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Исправить раскладку" : "Fix Keyboard Layout", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "keyboard"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                guard let presenter = hgPresenter(controllerInteraction) else {
                    return
                }
                let fixed = hgSwitchKeyboardLayout(message.text)
                let alert = UIAlertController(title: ru ? "Исправленная раскладка" : "Fixed Layout", message: fixed, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: ru ? "Скопировать" : "Copy", style: .default, handler: { _ in
                    UIPasteboard.general.string = fixed
                }))
                alert.addAction(UIAlertAction(title: chatPresentationInterfaceState.strings.Common_OK, style: .cancel))
                presenter.present(alert, animated: true)
            }
        }))
    case let .addToNote(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "В заметку о чате" : "Add to Chat Note", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "note.text.badge.plus"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            let peerIdValue = message.id.peerId.toInt64()
            let current = HolyGramNotes.note(peerId: peerIdValue) ?? ""
            let addition = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            HolyGramNotes.setNote(peerId: peerIdValue, text: current.isEmpty ? addition : current + "\n" + addition)
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controllerInteraction.presentGlobalOverlayController(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: ru ? "Добавлено в заметку о чате" : "Added to the chat note", timeout: 2.0, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
        }))
    case let .copyPlain(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Копировать без форматирования" : "Copy as Plain Text", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "textformat"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            UIPasteboard.general.setItems([[UTType.plainText.identifier: message.text]], options: [:])
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controllerInteraction.presentGlobalOverlayController(UndoOverlayController(presentationData: presentationData, content: .copy(text: ru ? "Скопировано без форматирования" : "Copied as plain text"), elevatedLayout: false, action: { _ in return false }), nil)
        }))
    case .speak:
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        let speaking = HolyGramSpeech.shared.isSpeaking
        return .action(ContextMenuActionItem(text: speaking ? (ru ? "Остановить озвучку" : "Stop Reading") : (ru ? "Озвучить" : "Read Aloud"), icon: { theme in
            return generateTintedImage(image: UIImage(systemName: speaking ? "stop.circle" : "speaker.wave.2"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            if speaking {
                HolyGramSpeech.shared.stop()
            } else {
                HolyGramSpeech.shared.speak(message.text)
            }
        }))
    case let .copyWithAuthor(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Копировать с автором" : "Copy with Author", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "doc.on.doc"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            let author = hgAuthorName(message: message, chatPresentationInterfaceState: chatPresentationInterfaceState)
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy HH:mm"
            let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
            UIPasteboard.general.string = "\(author), [\(date)]:\n\(message.text)"
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controllerInteraction.presentGlobalOverlayController(UndoOverlayController(presentationData: presentationData, content: .copy(text: ru ? "Скопировано с автором и датой" : "Copied with author and date"), elevatedLayout: false, action: { _ in return false }), nil)
        }))
    case let .writeToAuthor(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Написать автору" : "Message Author", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "bubble.left.and.text.bubble.right"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            guard let author = message.author, let navigationController = controllerInteraction.navigationController() else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(EnginePeer(author))))
        }))
    case let .messageCard(context, controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "Картинка сообщения" : "Message as Image", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "photo.on.rectangle"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgShareMessageCard(context: context, controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, message: message)
            }
        }))
    case let .firstMessage(controllerInteraction):
        let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
        return .action(ContextMenuActionItem(text: ru ? "К началу чата" : "Go to First Message", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "arrow.up.to.line"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            controllerInteraction.navigateToFirstDateMessage(1, false)
        }))
    case let .editHistory(controllerInteraction):
        return .action(ContextMenuActionItem(text: i18n("Message.HolyGram.EditHistory", chatPresentationInterfaceState.strings.baseLanguageCode), icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            Queue.mainQueue().after(0.3) {
                hgShowEditHistory(controllerInteraction: controllerInteraction, chatPresentationInterfaceState: chatPresentationInterfaceState, message: message)
            }
        }))
    }
}

// MARK: HolyGram: the author's name as shown in the chat
private func hgAuthorName(message: EngineRawMessage, chatPresentationInterfaceState: ChatPresentationInterfaceState) -> String {
    if let author = message.author {
        return EnginePeer(author).displayTitle(strings: chatPresentationInterfaceState.strings, displayOrder: chatPresentationInterfaceState.nameDisplayOrder)
    }
    if let peer = message.peers[message.id.peerId] {
        return EnginePeer(peer).displayTitle(strings: chatPresentationInterfaceState.strings, displayOrder: chatPresentationInterfaceState.nameDisplayOrder)
    }
    return "?"
}

// MARK: HolyGram: message ids, exact dates and the original sender of a forward
private func hgShowMessageInfo(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage, ru: Bool) {
    guard let presenter = hgPresenter(controllerInteraction) else {
        return
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
    let date: (Int32) -> String = { formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0))) }
    let rawPeerId = message.id.peerId.id._internalGetInt64Value()
    var chatId = "\(rawPeerId)"
    if message.id.peerId.namespace == Namespaces.Peer.CloudChannel {
        chatId = "-100\(rawPeerId)"
    } else if message.id.peerId.namespace == Namespaces.Peer.CloudGroup {
        chatId = "-\(rawPeerId)"
    }
    var lines: [String] = []
    lines.append((ru ? "ID сообщения: " : "Message ID: ") + "\(message.id.id)")
    lines.append((ru ? "ID чата: " : "Chat ID: ") + chatId)
    if let author = message.author {
        lines.append((ru ? "Автор: " : "Author: ") + hgAuthorName(message: message, chatPresentationInterfaceState: chatPresentationInterfaceState) + " (ID \(author.id.id._internalGetInt64Value()))")
    }
    lines.append((ru ? "Отправлено: " : "Sent: ") + date(message.timestamp))
    for attribute in message.attributes {
        if let edited = attribute as? EditedMessageAttribute {
            lines.append((ru ? "Изменено: " : "Edited: ") + date(edited.date))
        }
        if let views = attribute as? ViewCountMessageAttribute {
            lines.append((ru ? "Просмотры: " : "Views: ") + "\(views.count)")
        }
        if let forwards = attribute as? ForwardCountMessageAttribute {
            lines.append((ru ? "Пересылки: " : "Forwards: ") + "\(forwards.count)")
        }
    }
    if let forwardInfo = message.forwardInfo {
        var source = forwardInfo.authorSignature ?? ""
        if let author = forwardInfo.author {
            source = EnginePeer(author).displayTitle(strings: chatPresentationInterfaceState.strings, displayOrder: chatPresentationInterfaceState.nameDisplayOrder)
        }
        if source.isEmpty {
            source = ru ? "скрыт" : "hidden"
        }
        lines.append((ru ? "Переслано от: " : "Forwarded from: ") + source)
        lines.append((ru ? "Исходная дата: " : "Original date: ") + date(forwardInfo.date))
    }
    if !message.text.isEmpty {
        lines.append((ru ? "Символов: " : "Characters: ") + "\(message.text.count)")
    }
    let text = lines.joined(separator: "\n")
    let alert = UIAlertController(title: ru ? "Подробности" : "Details", message: text, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: ru ? "Скопировать" : "Copy", style: .default, handler: { _ in
        UIPasteboard.general.string = text
    }))
    alert.addAction(UIAlertAction(title: chatPresentationInterfaceState.strings.Common_OK, style: .cancel))
    presenter.present(alert, animated: true)
}

// MARK: HolyGram: reads a message aloud in its own language
final class HolyGramSpeech: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = HolyGramSpeech()
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        self.synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        self.stop()
        let utterance = AVSpeechUtterance(string: trimmed)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        if let language = recognizer.dominantLanguage, let voice = AVSpeechSynthesisVoice(language: language.rawValue) {
            utterance.voice = voice
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        self.isSpeaking = true
        self.synthesizer.speak(utterance)
    }

    func stop() {
        if self.synthesizer.isSpeaking {
            self.synthesizer.stopSpeaking(at: .immediate)
        }
        self.isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        self.isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        self.isSpeaking = false
    }
}

// MARK: HolyGram: a message drawn as a picture card, shared from the share sheet
private func hgShareMessageCard(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage) {
    guard let presenter = hgPresenter(controllerInteraction) else {
        return
    }
    let author = hgAuthorName(message: message, chatPresentationInterfaceState: chatPresentationInterfaceState)
    var text = message.text
    if text.count > 1500 {
        text = String(text.prefix(1500)) + "…"
    }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))

    let width: CGFloat = 1080.0
    let padding: CGFloat = 72.0
    let bubblePadding: CGFloat = 48.0
    let textWidth = width - padding * 2.0 - bubblePadding * 2.0
    let nameAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 44.0, weight: .semibold), .foregroundColor: UIColor(red: 0.78, green: 0.66, blue: 1.0, alpha: 1.0)]
    let textAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 46.0), .foregroundColor: UIColor.white]
    let footerAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 32.0), .foregroundColor: UIColor(white: 1.0, alpha: 0.55)]
    let name = NSAttributedString(string: author, attributes: nameAttributes)
    let body = NSAttributedString(string: text, attributes: textAttributes)
    let footer = NSAttributedString(string: date, attributes: footerAttributes)
    let brand = NSAttributedString(string: "HolyGram", attributes: [.font: UIFont.systemFont(ofSize: 34.0, weight: .semibold), .foregroundColor: UIColor(red: 1.0, green: 0.82, blue: 0.4, alpha: 0.9)])
    let bound: (NSAttributedString) -> CGSize = { string in
        return string.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral.size
    }
    let nameSize = bound(name)
    let bodySize = bound(body)
    let footerSize = bound(footer)
    let bubbleHeight = bubblePadding + nameSize.height + 16.0 + bodySize.height + 24.0 + footerSize.height + bubblePadding
    let height = padding + bubbleHeight + 40.0 + 50.0 + padding

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return format
    }())
    let image = renderer.image { rendererContext in
        let cg = rendererContext.cgContext
        let colors = [UIColor(red: 0.10, green: 0.06, blue: 0.26, alpha: 1.0).cgColor, UIColor(red: 0.28, green: 0.12, blue: 0.52, alpha: 1.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: width, y: height), options: [])
        }
        let bubbleRect = CGRect(x: padding, y: padding, width: width - padding * 2.0, height: bubbleHeight)
        UIColor(white: 1.0, alpha: 0.10).setFill()
        UIBezierPath(roundedRect: bubbleRect, cornerRadius: 44.0).fill()
        var y = bubbleRect.minY + bubblePadding
        name.draw(with: CGRect(x: bubbleRect.minX + bubblePadding, y: y, width: textWidth, height: nameSize.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += nameSize.height + 16.0
        body.draw(with: CGRect(x: bubbleRect.minX + bubblePadding, y: y, width: textWidth, height: bodySize.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += bodySize.height + 24.0
        footer.draw(at: CGPoint(x: bubbleRect.maxX - bubblePadding - footerSize.width, y: y))
        let brandSize = brand.size()
        brand.draw(at: CGPoint(x: (width - brandSize.width) / 2.0, y: bubbleRect.maxY + 40.0))
    }
    let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    presenter.present(activity, animated: true)
}

// MARK: HolyGram: every link of a message, from its entities and its plain text
private func hgPresentLinks(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage, ru: Bool) {
    guard let presenter = hgPresenter(controllerInteraction), let sourceView = controllerInteraction.navigationController()?.view else {
        return
    }
    var links: [String] = []
    let text = message.text as NSString
    for attribute in message.attributes {
        guard let entities = attribute as? TextEntitiesMessageAttribute else {
            continue
        }
        for entity in entities.entities {
            switch entity.type {
            case let .TextUrl(url):
                links.append(url)
            case .Url:
                if entity.range.upperBound <= text.length {
                    links.append(text.substring(with: NSRange(location: entity.range.lowerBound, length: entity.range.count)))
                }
            default:
                break
            }
        }
    }
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        for match in detector.matches(in: message.text, options: [], range: NSRange(location: 0, length: text.length)) {
            if let url = match.url?.absoluteString {
                links.append(url)
            }
        }
    }
    for media in message.media {
        if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
            links.append(content.url)
        }
    }
    var seen = Set<String>()
    links = links.filter { seen.insert($0.lowercased()).inserted }

    let sheet = UIAlertController(title: ru ? "Ссылки из сообщения" : "Links in Message", message: links.isEmpty ? (ru ? "В сообщении нет ссылок." : "No links in this message.") : nil, preferredStyle: .actionSheet)
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    for link in links.prefix(20) {
        sheet.addAction(UIAlertAction(title: String(link.prefix(70)), style: .default, handler: { _ in
            context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: link, forceExternal: false, presentationData: presentationData, navigationController: controllerInteraction.navigationController(), dismissInput: {})
        }))
    }
    if !links.isEmpty {
        sheet.addAction(UIAlertAction(title: ru ? "Скопировать все (\(links.count))" : "Copy All (\(links.count))", style: .default, handler: { _ in
            UIPasteboard.general.string = links.joined(separator: "\n")
        }))
    }
    sheet.addAction(UIAlertAction(title: chatPresentationInterfaceState.strings.Common_Cancel, style: .cancel))
    if let popover = sheet.popoverPresentationController {
        popover.sourceView = sourceView
        popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    presenter.present(sheet, animated: true)
}

// MARK: HolyGram: schedules the same text in this chat for later
private func hgPresentScheduleRepeat(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage, ru: Bool) {
    guard let presenter = hgPresenter(controllerInteraction), let sourceView = controllerInteraction.navigationController()?.view else {
        return
    }
    let text = message.text
    let entities = message.attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first
    let delays: [Int32] = [3600, 10800, 86400, 604800]
    let titles: [String]
    if ru {
        titles = ["Через 1 час", "Через 3 часа", "Завтра в это же время", "Через неделю"]
    } else {
        titles = ["In 1 hour", "In 3 hours", "Tomorrow, same time", "In a week"]
    }
    let options: [(String, Int32)] = Array(zip(titles, delays))
    let sheet = UIAlertController(title: ru ? "Отправить ещё раз" : "Send Again", message: ru ? "Сообщение будет запланировано в этом чате. Его видно в «Отложенных»." : "The message is scheduled in this chat. You'll find it in Scheduled Messages.", preferredStyle: .actionSheet)
    for (title, delay) in options {
        sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
            var attributes: [MessageAttribute] = [OutgoingScheduleInfoMessageAttribute(scheduleTime: Int32(Date().timeIntervalSince1970) + delay, repeatPeriod: nil)]
            if let entities {
                attributes.append(entities)
            }
            let _ = enqueueMessages(account: context.account, peerId: message.id.peerId, messages: [
                .message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: chatPresentationInterfaceState.chatLocation.threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            ]).startStandalone()
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controllerInteraction.presentGlobalOverlayController(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: ru ? "Запланировано: \(title.lowercased())" : "Scheduled: \(title.lowercased())", timeout: 2.5, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
        }))
    }
    sheet.addAction(UIAlertAction(title: chatPresentationInterfaceState.strings.Common_Cancel, style: .cancel))
    if let popover = sheet.popoverPresentationController {
        popover.sourceView = sourceView
        popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    presenter.present(sheet, animated: true)
}

// MARK: HolyGram: the original file of a voice/video message, document, music or photo, via the share sheet
private func hgShareMessageFile(context: AccountContext, controllerInteraction: ChatControllerInteraction, message: EngineRawMessage, ru: Bool) {
    var resource: MediaResource?
    var media: Media?
    var fileName = "HolyGram-\(message.id.id)"
    var contentType: MediaResourceUserContentType = .file
    for item in message.media {
        if let file = item as? TelegramMediaFile {
            resource = file.resource
            media = file
            if let name = file.fileName, !name.isEmpty {
                fileName = name
            } else {
                let ext: String
                if file.isVoice {
                    ext = "ogg"
                    contentType = .audio
                } else if file.isInstantVideo || file.isVideo {
                    ext = "mp4"
                    contentType = .video
                } else if file.mimeType.hasPrefix("audio/") {
                    ext = file.mimeType == "audio/mpeg" ? "mp3" : "m4a"
                    contentType = .audio
                } else {
                    ext = file.mimeType.split(separator: "/").last.map(String.init) ?? "bin"
                }
                fileName += "." + ext
            }
            break
        } else if let image = item as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
            resource = representation.resource
            media = image
            fileName += ".jpg"
            contentType = .image
            break
        }
    }
    guard let resource, let media else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    controllerInteraction.presentGlobalOverlayController(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: ru ? "Готовлю файл…" : "Preparing the file…", timeout: 2.0, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
    let mediaBox = context.account.postbox.mediaBox
    let reference = AnyMediaReference.message(message: MessageReference(message), media: media).resourceReference(resource)
    let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(message.id.peerId), userContentType: contentType, reference: reference).startStandalone()
    let _ = (mediaBox.resourceData(resource)
    |> filter { $0.complete }
    |> take(1)
    |> deliverOnMainQueue).start(next: { data in
        fetch.dispose()
        let safeName = String(fileName.map { "/\\:?*\"<>|".contains($0) ? "_" : $0 })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("holygram-share-\(Int64.random(in: 1 ..< Int64.max))", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(safeName)
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: data.path), to: url)
        } catch {
            return
        }
        guard let presenter = hgPresenter(controllerInteraction) else {
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
}

// MARK: HolyGram: a QR code of the message's first link, or of its text
private func hgShareQrCode(controllerInteraction: ChatControllerInteraction, message: EngineRawMessage, ru: Bool) {
    guard let presenter = hgPresenter(controllerInteraction) else {
        return
    }
    var content = message.text
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue), let match = detector.firstMatch(in: message.text, options: [], range: NSRange(location: 0, length: (message.text as NSString).length)), let url = match.url {
        content = url.absoluteString
    }
    content = String(content.prefix(1200))
    guard let data = content.data(using: .utf8), let filter = CIFilter(name: "CIQRCodeGenerator") else {
        return
    }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else {
        return
    }
    let scale = 1000.0 / output.extent.width
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
        return
    }
    let size = CGSize(width: scaled.extent.width + 120.0, height: scaled.extent.height + 120.0)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        context.cgContext.interpolationQuality = .none
        UIImage(cgImage: cgImage).draw(in: CGRect(x: 60.0, y: 60.0, width: scaled.extent.width, height: scaled.extent.height))
    }
    let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    presenter.present(activity, animated: true)
}

// MARK: HolyGram: text typed on the wrong keyboard (ghbdtn → привет and back)
func hgSwitchKeyboardLayout(_ text: String) -> String {
    let latin = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?")
    let cyrillic = Array("ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,")
    var latinToCyrillic: [Character: Character] = [:]
    var cyrillicToLatin: [Character: Character] = [:]
    for (l, c) in zip(latin, cyrillic) {
        latinToCyrillic[l] = c
        if cyrillicToLatin[c] == nil {
            cyrillicToLatin[c] = l
        }
    }
    let letters = text.filter { $0.isLetter }
    let cyrillicCount = letters.filter { cyrillicToLatin[$0] != nil }.count
    // Mostly Cyrillic letters: it was English typed on the Russian layout, and the other way round.
    let toLatin = cyrillicCount * 2 > letters.count
    return String(text.map { character in
        if toLatin {
            return cyrillicToLatin[character] ?? character
        }
        return latinToCyrillic[character] ?? character
    })
}

// MARK: HolyGram: the topmost view controller of the chat's window
private func hgPresenter(_ controllerInteraction: ChatControllerInteraction) -> UIViewController? {
    guard let navigationController = controllerInteraction.navigationController(), var presenter = navigationController.view.window?.rootViewController else {
        return nil
    }
    while let presented = presenter.presentedViewController {
        presenter = presented
    }
    return presenter
}

// MARK: HolyGram: send a saved template to this chat, or save this message as one
private func hgPresentTemplates(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage, ru: Bool) {
    guard let presenter = hgPresenter(controllerInteraction), let sourceView = controllerInteraction.navigationController()?.view else {
        return
    }
    let strings = chatPresentationInterfaceState.strings
    let sheet = UIAlertController(title: ru ? "Шаблоны" : "Templates", message: nil, preferredStyle: .actionSheet)
    let templates = HolyGramTemplates.all()
    if templates.isEmpty {
        sheet.message = ru ? "Шаблонов пока нет." : "No templates yet."
    }
    for template in templates.reversed().prefix(15) {
        let title = String(template.replacingOccurrences(of: "\n", with: " ").prefix(60))
        sheet.addAction(UIAlertAction(title: "↗︎ " + title, style: .default, handler: { _ in
            let _ = enqueueMessages(account: context.account, peerId: message.id.peerId, messages: [
                .message(text: template, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: chatPresentationInterfaceState.chatLocation.threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            ]).startStandalone()
        }))
    }
    if !message.text.isEmpty {
        sheet.addAction(UIAlertAction(title: ru ? "Сохранить это сообщение как шаблон" : "Save This Message as Template", style: .default, handler: { _ in
            HolyGramTemplates.add(message.text)
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controllerInteraction.presentGlobalOverlayController(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: ru ? "Шаблон сохранён." : "Template saved.", timeout: 2.0, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
        }))
    }
    sheet.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel))
    if let popover = sheet.popoverPresentationController {
        popover.sourceView = sourceView
        popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    presenter.present(sheet, animated: true)
}

// MARK: HolyGram: the chat's stored messages as a plain text file
private func hgExportChatText(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, peerId: PeerId, ru: Bool) {
    let strings = chatPresentationInterfaceState.strings
    let nameOrder = chatPresentationInterfaceState.nameDisplayOrder
    let maxMessages = 100000
    let _ = (context.account.postbox.transaction { transaction -> (String, String, Int) in
        var lines: [(Int32, Int32, String)] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        var names: [PeerId: String] = [:]
        transaction.withAllMessages(peerId: peerId, reversed: true, { message in
            var text = message.text
            if text.isEmpty {
                if message.media.contains(where: { $0 is TelegramMediaAction }) {
                    return true
                }
                text = message.media.isEmpty ? "" : (ru ? "[медиа]" : "[media]")
            } else if !message.media.isEmpty {
                text = (ru ? "[медиа] " : "[media] ") + text
            }
            var author = ""
            if let authorPeer = message.author {
                if let name = names[authorPeer.id] {
                    author = name
                } else {
                    author = EnginePeer(authorPeer).displayTitle(strings: strings, displayOrder: nameOrder)
                    names[authorPeer.id] = author
                }
            }
            let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
            lines.append((message.timestamp, message.id.id, "[\(date)] \(author): \(text)"))
            return lines.count < maxMessages
        })
        lines.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        let title = transaction.getPeer(peerId).flatMap { EnginePeer($0).displayTitle(strings: strings, displayOrder: nameOrder) } ?? "Chat"
        return (title, lines.map { $0.2 }.joined(separator: "\n"), lines.count)
    }
    |> deliverOnMainQueue).start(next: { title, text, count in
        guard let presenter = hgPresenter(controllerInteraction) else {
            return
        }
        if count == 0 {
            let alert = UIAlertController(title: nil, message: ru ? "На устройстве нет сообщений этого чата. Пролистайте историю, чтобы она загрузилась." : "No messages of this chat are stored on this device. Scroll back through the history to load it.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: strings.Common_OK, style: .default))
            presenter.present(alert, animated: true)
            return
        }
        let safeTitle = String(title.map { "/\\:?*\"<>|".contains($0) ? "_" : $0 }).prefix(60)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeTitle).txt")
        let header = "\(title)\n" + (ru ? "Сообщений: \(count). Экспорт HolyGram, только загруженные на устройство сообщения." : "Messages: \(count). Exported by HolyGram, messages stored on this device only.") + "\n\n"
        do {
            try (header + text).write(to: url, atomically: true, encoding: .utf8)
        } catch {
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
}

// MARK: HolyGram: every photo and video of a chat into the Photos library
private func hgSaveAllChatMedia(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, peerId: PeerId, ru: Bool) {
    guard let navigationController = controllerInteraction.navigationController(), var presenter = navigationController.view.window?.rootViewController else {
        return
    }
    while let presented = presenter.presentedViewController {
        presenter = presented
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let toast: (String) -> Void = { text in
        controllerInteraction.presentGlobalOverlayController(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: 4.0, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), nil)
    }
    let maxItems = 2000

    let start = {
        toast(ru ? "Ищу фото и видео в чате…" : "Looking for photos and videos…")
        var collected: [(EngineRawMessage, Media)] = []
        func fetchPage(_ state: SearchMessagesState?) {
            let _ = (context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: .photoOrVideo, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: state, limit: 100)
            |> take(1)
            |> deliverOnMainQueue).start(next: { result, nextState in
                for message in result.messages {
                    for media in message.media where media is TelegramMediaImage || (media as? TelegramMediaFile)?.isVideo == true {
                        collected.append((message, media))
                    }
                }
                if result.completed || result.messages.isEmpty || collected.count >= maxItems {
                    saveAll(Array(collected.prefix(maxItems)))
                } else {
                    fetchPage(nextState)
                }
            })
        }
        func saveAll(_ items: [(EngineRawMessage, Media)]) {
            if items.isEmpty {
                toast(ru ? "В этом чате нет фото и видео." : "No photos or videos in this chat.")
                return
            }
            toast(ru ? "Сохраняю \(items.count) файлов в «Фото». Не закрывайте HolyGram." : "Saving \(items.count) files to Photos. Keep HolyGram open.")
            var saved = 0
            func next(_ index: Int) {
                if index >= items.count {
                    toast(ru ? "Готово: сохранено \(saved) из \(items.count)." : "Done: saved \(saved) of \(items.count).")
                    return
                }
                let (message, media) = items[index]
                let _ = (saveToCameraRoll(context: context, userLocation: .peer(peerId), mediaReference: .message(message: MessageReference(message), media: media))
                |> deliverOnMainQueue).start(completed: {
                    saved += 1
                    if saved % 50 == 0 {
                        toast(ru ? "Сохранено \(saved) из \(items.count)…" : "Saved \(saved) of \(items.count)…")
                    }
                    next(index + 1)
                })
            }
            next(0)
        }
        fetchPage(nil)
    }

    let alert = UIAlertController(title: ru ? "Сохранить все фото и видео?" : "Save all photos and videos?", message: ru ? "Все фото и видео из этого чата (до \(maxItems)) будут скачаны и сохранены в «Фото». Это может занять время и место." : "All photos and videos from this chat (up to \(maxItems)) will be downloaded and saved to Photos. This can take a while and use storage.", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
    alert.addAction(UIAlertAction(title: ru ? "Сохранить" : "Save", style: .default, handler: { _ in start() }))
    presenter.present(alert, animated: true)
}

// MARK: HolyGram: who writes how much and when, over the messages stored on this device
private func hgShowChatStatistics(context: AccountContext, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, peerId: PeerId, ru: Bool) {
    let strings = chatPresentationInterfaceState.strings
    let nameOrder = chatPresentationInterfaceState.nameDisplayOrder
    let _ = (context.account.postbox.transaction { transaction -> String in
        var total = 0
        var byAuthor: [PeerId: Int] = [:]
        var byHour = [Int](repeating: 0, count: 24)
        var firstTimestamp: Int32 = Int32.max
        let calendar = Calendar.current
        transaction.withAllMessages(peerId: peerId, reversed: true, { message in
            if message.media.contains(where: { $0 is TelegramMediaAction }) {
                return true
            }
            total += 1
            if let authorId = message.author?.id {
                byAuthor[authorId, default: 0] += 1
            }
            byHour[calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))] += 1
            firstTimestamp = min(firstTimestamp, message.timestamp)
            return total < 200000
        })
        if total == 0 {
            return ru ? "На устройстве нет сообщений этого чата. Пролистайте историю, чтобы она загрузилась." : "No messages of this chat are stored on this device. Scroll back through the history to load it."
        }
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        lines.append(ru ? "Сообщений: \(total)" : "Messages: \(total)")
        if firstTimestamp != Int32.max {
            lines.append((ru ? "С " : "Since ") + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(firstTimestamp))))
        }
        lines.append("")
        lines.append(ru ? "Кто пишет больше:" : "Top writers:")
        for (authorId, count) in byAuthor.sorted(by: { $0.value > $1.value }).prefix(10) {
            let name = transaction.getPeer(authorId).flatMap { EnginePeer($0).displayTitle(strings: strings, displayOrder: nameOrder) } ?? "?"
            let percent = Int((Double(count) / Double(total) * 100.0).rounded())
            lines.append("\(name) — \(count) (\(percent)%)")
        }
        let busiest = byHour.enumerated().sorted(by: { $0.element > $1.element }).prefix(3).filter { $0.element > 0 }.map { String(format: "%02d:00", $0.offset) }
        if !busiest.isEmpty {
            lines.append("")
            lines.append((ru ? "Самые активные часы: " : "Busiest hours: ") + busiest.joined(separator: ", "))
        }
        lines.append("")
        lines.append(ru ? "По сообщениям, загруженным на это устройство." : "Based on the messages stored on this device.")
        return lines.joined(separator: "\n")
    }
    |> deliverOnMainQueue).start(next: { text in
        guard let navigationController = controllerInteraction.navigationController(), var presenter = navigationController.view.window?.rootViewController else {
            return
        }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let alert = UIAlertController(title: ru ? "Статистика чата" : "Chat Statistics", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: strings.Common_OK, style: .default))
        presenter.present(alert, animated: true)
    })
}

// MARK: HolyGram: local reminder about a message
private func hgPresentReminderOptions(controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage, ru: Bool) {
    guard let navigationController = controllerInteraction.navigationController(), var presenter = navigationController.view.window?.rootViewController else {
        return
    }
    while let presented = presenter.presentedViewController {
        presenter = presented
    }
    let chatTitle = chatPresentationInterfaceState.renderedPeer?.peer.flatMap { EnginePeer($0).displayTitle(strings: chatPresentationInterfaceState.strings, displayOrder: chatPresentationInterfaceState.nameDisplayOrder) } ?? "HolyGram"
    var body = message.text.replacingOccurrences(of: "\n", with: " ")
    if body.isEmpty {
        body = ru ? "Сообщение с медиа" : "Message with media"
    }

    func schedule(after seconds: TimeInterval?, at components: DateComponents?) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound], completionHandler: { granted, _ in
            guard granted else {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = (ru ? "Напоминание: " : "Reminder: ") + chatTitle
            content.body = String(body.prefix(300))
            content.sound = .default
            let trigger: UNNotificationTrigger
            if let components {
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            } else {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60.0, seconds ?? 3600.0), repeats: false)
            }
            center.add(UNNotificationRequest(identifier: "holygram-reminder-\(UUID().uuidString)", content: content, trigger: trigger))
        })
    }

    let sheet = UIAlertController(title: ru ? "Напомнить о сообщении" : "Remind me about this message", message: nil, preferredStyle: .actionSheet)
    sheet.addAction(UIAlertAction(title: ru ? "Через 1 час" : "In 1 hour", style: .default, handler: { _ in schedule(after: 3600, at: nil) }))
    sheet.addAction(UIAlertAction(title: ru ? "Через 3 часа" : "In 3 hours", style: .default, handler: { _ in schedule(after: 3 * 3600, at: nil) }))
    sheet.addAction(UIAlertAction(title: ru ? "Завтра в 9:00" : "Tomorrow at 9:00", style: .default, handler: { _ in
        var tomorrow = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
        tomorrow.hour = 9
        tomorrow.minute = 0
        schedule(after: nil, at: tomorrow)
    }))
    sheet.addAction(UIAlertAction(title: chatPresentationInterfaceState.strings.Common_Cancel, style: .cancel, handler: nil))
    if let popover = sheet.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1.0, height: 1.0)
    }
    presenter.present(sheet, animated: true)
}

// MARK: HolyGram
private func hgShowEditHistory(controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState, message: EngineRawMessage) {
    guard let navigationController = controllerInteraction.navigationController(), var presenter = navigationController.view.window?.rootViewController else {
        return
    }
    while let presented = presenter.presentedViewController {
        presenter = presented
    }
    let lang = chatPresentationInterfaceState.strings.baseLanguageCode
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: lang)
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    func dateString(_ timestamp: Int32) -> String {
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    let history = message.holyGramEditHistory
    var parts: [String] = []
    for (index, entry) in history.enumerated() {
        let title = index == 0 ? i18n("Message.HolyGram.EditHistory.Original", lang) : "#\(index + 1)"
        parts.append("\(title) · \(dateString(entry.date))\n\(entry.text)")
    }
    let currentDate = message.editedTime ?? message.timestamp
    parts.append("\(i18n("Message.HolyGram.EditHistory.Current", lang)) · \(dateString(currentDate))\n\(message.text)")

    let alert = UIAlertController(title: i18n("Message.HolyGram.EditHistory", lang), message: parts.joined(separator: "\n\n———\n\n"), preferredStyle: .alert)
    if !message.isCopyProtected() {
        alert.addAction(UIAlertAction(title: chatPresentationInterfaceState.strings.Conversation_ContextMenuCopy, style: .default, handler: { _ in
            UIPasteboard.general.string = history.map(\.text).joined(separator: "\n\n")
        }))
    }
    alert.addAction(UIAlertAction(title: chatPresentationInterfaceState.strings.Common_Close, style: .cancel, handler: nil))
    presenter.present(alert, animated: true)
}

func sgMakeSelectFromUserContextMenuAction(context: AccountContext, chatPresentationInterfaceState: ChatPresentationInterfaceState, controllerInteraction: ChatControllerInteraction, interfaceInteraction: ChatPanelInterfaceInteraction, message: EngineRawMessage) -> ContextMenuItem? {
    guard let authorId = message.author?.id else {
        return nil
    }
    return .action(ContextMenuActionItem(text: i18n("ContextMenu.SelectFromUser", chatPresentationInterfaceState.strings.baseLanguageCode), icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/SelectAll"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        let progressSignal = Signal<Never, NoError> { _ in
            let overlayController = OverlayStatusController(theme: chatPresentationInterfaceState.theme, type: .loading(cancelled: nil))
            controllerInteraction.presentGlobalOverlayController(overlayController, nil)
            return ActionDisposable { [weak overlayController] in
                Queue.mainQueue().async {
                    overlayController?.dismiss()
                }
            }
        }
        |> runOn(Queue.mainQueue())
        |> delay(0.2, queue: Queue.mainQueue())
        let progressDisposable = progressSignal.start()
        let _ = (context.account.postbox.transaction { transaction -> [MessageId] in
            let limit = 500
            var result: [MessageId] = []
            let needThreadIdFilter: Bool
            let searchThreadId: Int64?
            switch chatPresentationInterfaceState.chatLocation {
            case let .replyThread(replyThreadMessage):
                needThreadIdFilter = true
                searchThreadId = replyThreadMessage.threadId
            default:
                needThreadIdFilter = false
                searchThreadId = nil
            }
            transaction.withAllMessages(peerId: message.id.peerId, reversed: true, { searchMessage in
                if result.count >= limit {
                    return false
                }
                if searchMessage.author?.id == authorId {
                    if needThreadIdFilter && searchMessage.threadId != searchThreadId {
                        return true
                    }
                    if searchMessage.media.contains(where: { $0 is TelegramMediaAction }) {
                        return true
                    }
                    result.append(searchMessage.id)
                }
                return true
            })
            return result
        }
        |> deliverOnMainQueue)
        .start(next: { ids in
            interfaceInteraction.beginMessageSelection(ids, { transition in
                f(.custom(transition))
            })
            Queue.mainQueue().async {
                progressDisposable.dispose()
            }
        }, completed: {
            Queue.mainQueue().async {
                progressDisposable.dispose()
            }
        })
    }))
}

func sgInsertContextMenu(actions: inout [ContextMenuItem], sgActions: inout [ContextMenuItem], hgActions: [ContextMenuItem] = [], index: Int?, chatPresentationInterfaceState: ChatPresentationInterfaceState) {
    let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
    // MARK: HolyGram: HolyGram's items get their own submenu next to the original one
    var subMenus: [ContextMenuItem] = []
    if let menu = sgMakeSubMenu(title: "HolyGram", icon: { theme in
        return generateTintedImage(image: UIImage(systemName: "sparkles"), color: theme.actionSheet.primaryTextColor)
    }, items: hgActions, chatPresentationInterfaceState: chatPresentationInterfaceState) {
        subMenus.append(menu)
    }
    if let menu = sgMakeSubMenu(title: ru ? "Ещё" : "More", icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "SwiftgramContextMenu"), color: theme.actionSheet.primaryTextColor)
    }, items: sgActions, chatPresentationInterfaceState: chatPresentationInterfaceState) {
        subMenus.append(menu)
    }
    guard !subMenus.isEmpty else {
        return
    }
    var inserted: [ContextMenuItem] = []
    if !actions.isEmpty {
        inserted.append(.separator)
    }
    inserted.append(contentsOf: subMenus)
    if let index, index <= actions.count {
        actions.insert(contentsOf: inserted, at: index)
    } else {
        actions.append(contentsOf: inserted)
    }
}

/// MARK: HolyGram: the HolyGram submenu, split into sections so every list fits on screen
/// (context menu lists don't scroll). With few items they stay one flat list.
func sgHolyGramSections(_ groups: [String: [ContextMenuItem]], chatPresentationInterfaceState: ChatPresentationInterfaceState) -> [ContextMenuItem] {
    let ru = chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("ru") || chatPresentationInterfaceState.strings.baseLanguageCode.hasPrefix("uk")
    let order: [(String, String, String)] = [
        ("send", ru ? "Отправка" : "Sending", "paperplane"),
        ("copy", ru ? "Копировать и сохранить" : "Copy & Save", "square.and.arrow.down.on.square"),
        ("tools", ru ? "Инфо и инструменты" : "Info & Tools", "wrench.and.screwdriver")
    ]
    let total = groups.values.reduce(0) { $0 + $1.count }
    if total <= 7 {
        return order.flatMap { groups[$0.0] ?? [] }
    }
    var result: [ContextMenuItem] = []
    for (key, title, symbol) in order {
        guard let items = groups[key], !items.isEmpty else {
            continue
        }
        if items.count == 1 {
            result.append(contentsOf: items)
            continue
        }
        if let menu = sgMakeSubMenu(title: "\(title) (\(items.count))", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: symbol), color: theme.actionSheet.primaryTextColor)
        }, items: items, chatPresentationInterfaceState: chatPresentationInterfaceState) {
            result.append(menu)
        }
    }
    return result
}

/// A context menu row that opens `items` as a submenu with a Back row on top.
func sgMakeSubMenu(title: String, icon: @escaping (PresentationTheme) -> UIImage?, items: [ContextMenuItem], chatPresentationInterfaceState: ChatPresentationInterfaceState) -> ContextMenuItem? {
    guard !items.isEmpty else {
        return nil
    }
    var popItems: (() -> Void)? = nil
    var subItems = items
    subItems.insert(.action(ContextMenuActionItem(text: chatPresentationInterfaceState.strings.Common_Back, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.actionSheet.primaryTextColor)
    }, iconPosition: .left, action: { _, _ in
        popItems?()
    })), at: 0)
    subItems.insert(.separator, at: 1)
    let finalItems = subItems
    return .action(ContextMenuActionItem(text: title, icon: icon, action: { c, _ in
        popItems = { [weak c] in
            c?.popItems()
        }
        c?.pushItems(items: .single(ContextController.Items(content: .list(finalItems))))
    }))
}

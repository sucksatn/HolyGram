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
        navigationController?.pushViewController(sgSettingsController(context: context))
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

func sgInsertContextMenu(actions: inout [ContextMenuItem], sgActions: inout [ContextMenuItem], index: Int?, chatPresentationInterfaceState: ChatPresentationInterfaceState) {
    guard !sgActions.isEmpty else {
        return
    }
    if !actions.isEmpty {
        if let index {
            actions.insert(.separator, at: index)
        } else {
            actions.append(.separator)
        }
    }
    var popSGItems: (() -> Void)? = nil
    sgActions.insert(.action(ContextMenuActionItem(text: chatPresentationInterfaceState.strings.Common_Back, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.actionSheet.primaryTextColor)
    }, iconPosition: .left, action: { _, _ in
        popSGItems?()
    })), at: 0)
    sgActions.insert(.separator, at: 1)
    let sgItems = sgActions
    let swiftgramSubMenu: ContextMenuItem = .action(ContextMenuActionItem(text: "HolyGram", icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "SwiftgramContextMenu"), color: theme.actionSheet.primaryTextColor)
    }, action: { c, _ in
        popSGItems = { [weak c] in
            c?.popItems()
        }
        c?.pushItems(items: .single(ContextController.Items(content: .list(sgItems))))
    }))
    if let index {
        actions.insert(swiftgramSubMenu, at: index + 1)
    } else {
        actions.append(swiftgramSubMenu)
    }
}

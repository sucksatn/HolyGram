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
import ChatControllerInteraction
import ChatPresentationInterfaceState

func sgHandleInternalUrlRoute(context: AccountContext, parsedUrl: URL, navigationController: NavigationController?) -> Bool {
    guard let path = parsedUrl.pathComponents.last else {
        return false
    }
    switch path {
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

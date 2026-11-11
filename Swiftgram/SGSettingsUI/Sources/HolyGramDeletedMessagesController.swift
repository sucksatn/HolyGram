// MARK: HolyGram: every message kept after deletion, newest first, with search
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGItemListUI
import SGSimpleSettings

private enum DeletedMessagesSection: Int32, SGItemListSection {
    case search
    case messages
    case notice
    case clear
}

private typealias DeletedMessagesEntry = SGItemListUIEntry<DeletedMessagesSection, AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

/// Shows up to this many of the newest kept messages.
private let deletedMessagesLimit = 300

public func holyGramDeletedMessagesController(context: AccountContext) -> ViewController {
    let ids = HolyGramDeletedIndex.entries().prefix(deletedMessagesLimit).map { entry in
        EngineMessage.Id(peerId: EnginePeer.Id(entry.peerId), namespace: entry.namespace, id: entry.id)
    }
    return holyGramStoredMessagesController(context: context, ids: Array(ids), title: ("Удалённые сообщения", "Deleted Messages"), empty: ("Здесь появятся сообщения, которые удалили собеседники. Включите «Сохранять удалённые сообщения».", "Messages others delete will show up here. Turn on Keep Deleted Messages."), clear: { completion in
        // The kept copies exist only on this device: removing them locally removes them for good.
        let allIds = HolyGramDeletedIndex.entries().map { entry in
            EngineMessage.Id(peerId: EnginePeer.Id(entry.peerId), namespace: entry.namespace, id: entry.id)
        }
        let _ = (context.engine.messages.deleteMessagesInteractively(messageIds: allIds, type: .forLocalPeer)
        |> deliverOnMainQueue).start(completed: {
            HolyGramDeletedIndex.clear()
            completion()
        })
    })
}

public func holyGramBookmarksController(context: AccountContext) -> ViewController {
    let ids = HolyGramBookmarks.entries().map { peerId, namespace, id in
        EngineMessage.Id(peerId: EnginePeer.Id(peerId), namespace: namespace, id: id)
    }
    return holyGramStoredMessagesController(context: context, ids: ids, title: ("Закладки", "Bookmarks"), empty: ("Закладок нет. Удерживайте сообщение и выберите «В закладки».", "No bookmarks yet. Long-press a message and choose Bookmark."))
}

/// A searchable list of messages by id that opens each one in its chat.
private func holyGramStoredMessagesController(context: AccountContext, ids: [EngineMessage.Id], title: (String, String), empty: (String, String), clear: ((@escaping () -> Void) -> Void)? = nil) -> ViewController {
    let query = ValuePromise<String>("", ignoreRepeated: true)
    let cleared = ValuePromise<Bool>(false, ignoreRepeated: true)
    var presentImpl: ((ViewController) -> Void)?
    var openMessageImpl: ((EngineMessage.Id) -> Void)?

    let messagesSignal: Signal<[EngineMessage], NoError> = {
        // The index is shared by all accounts on the device; this account resolves only its own messages.
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Messages.Message.init)))
        |> map { messages -> [EngineMessage] in
            return ids.compactMap { messages[$0] ?? nil }
        }
    }()

    let arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, action: { action in
        if action == AnyHashable("hgClear"), let clear {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
            presentImpl?(textAlertController(context: context, title: ru ? "Очистить удалённые сообщения?" : "Clear deleted messages?", text: ru ? "Сохранённые копии удалённых сообщений сотрутся с этого устройства навсегда." : "The kept copies of deleted messages are erased from this device for good.", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: ru ? "Очистить" : "Clear", action: {
                    clear {
                        cleared.set(true)
                    }
                })
            ]))
            return
        }
        guard let messageId = action.base as? EngineMessage.Id else {
            return
        }
        openMessageImpl?(messageId)
    }, searchInput: { text in
        query.set(text)
    })

    let signal = combineLatest(context.sharedContext.presentationData, messagesSignal, query.get(), cleared.get())
    |> map { presentationData, messages, query, isCleared -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let messages = isCleared ? [] : messages
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: presentationData.strings.baseLanguageCode)
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var entries: [DeletedMessagesEntry] = []
        var id = 0
        entries.append(.searchInput(id: id, section: .search, title: NSAttributedString(string: "🔍"), text: query, placeholder: presentationData.strings.Common_Search))
        id += 1

        var shown = 0
        for message in messages {
            let chatTitle = message.peers[message.id.peerId].flatMap { EnginePeer($0).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) } ?? ""
            let author = message.author?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? ""
            var preview = message.text.replacingOccurrences(of: "\n", with: " ")
            if preview.isEmpty {
                preview = message.media.isEmpty ? "…" : (ru ? "[медиа]" : "[media]")
            }
            if !needle.isEmpty && !preview.lowercased().contains(needle) && !chatTitle.lowercased().contains(needle) && !author.lowercased().contains(needle) {
                continue
            }
            let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
            let from = (author.isEmpty || author == chatTitle) ? chatTitle : "\(chatTitle) · \(author)"
            let text = "\(from) · \(date)\n\(String(preview.prefix(160)))"
            entries.append(.action(id: id, section: .messages, actionType: AnyHashable(message.id), text: text, kind: .generic))
            id += 1
            shown += 1
        }

        let notice: String
        if messages.isEmpty {
            notice = ru ? empty.0 : empty.1
        } else if shown == 0 {
            notice = ru ? "Ничего не найдено." : "Nothing found."
        } else {
            notice = ru ? "Нажмите на сообщение, чтобы открыть его в чате." : "Tap a message to open it in its chat."
        }
        entries.append(.notice(id: id, section: .notice, text: notice))
        id += 1
        if clear != nil && !messages.isEmpty {
            entries.append(.action(id: id, section: .clear, actionType: AnyHashable("hgClear"), text: ru ? "Очистить все" : "Clear All", kind: .destructive))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? title.0 : title.1), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    openMessageImpl = { [weak controller] messageId in
        guard let navigationController = controller?.navigationController as? NavigationController else {
            return
        }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: messageId.peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false)))
        })
    }
    return controller
}

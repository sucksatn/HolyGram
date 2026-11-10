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
}

private typealias DeletedMessagesEntry = SGItemListUIEntry<DeletedMessagesSection, AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

/// Shows up to this many of the newest kept messages.
private let deletedMessagesLimit = 300

public func holyGramDeletedMessagesController(context: AccountContext) -> ViewController {
    let query = ValuePromise<String>("", ignoreRepeated: true)
    var openMessageImpl: ((EngineMessage.Id) -> Void)?

    let messagesSignal: Signal<[EngineMessage], NoError> = {
        let ids = HolyGramDeletedIndex.entries().prefix(deletedMessagesLimit).map { entry in
            EngineMessage.Id(peerId: EnginePeer.Id(entry.peerId), namespace: entry.namespace, id: entry.id)
        }
        // The index is shared by all accounts on the device; this account resolves only its own messages.
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Messages.Message.init)))
        |> map { messages -> [EngineMessage] in
            return ids.compactMap { messages[$0] ?? nil }
        }
    }()

    let arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, action: { action in
        guard let messageId = action.base as? EngineMessage.Id else {
            return
        }
        openMessageImpl?(messageId)
    }, searchInput: { text in
        query.set(text)
    })

    let signal = combineLatest(context.sharedContext.presentationData, messagesSignal, query.get())
    |> map { presentationData, messages, query -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
            notice = ru ? "Здесь появятся сообщения, которые удалили собеседники. Включите «Сохранять удалённые сообщения»." : "Messages others delete will show up here. Turn on Keep Deleted Messages."
        } else if shown == 0 {
            notice = ru ? "Ничего не найдено." : "Nothing found."
        } else {
            notice = ru ? "Нажмите на сообщение, чтобы открыть его в чате." : "Tap a message to open it in its chat."
        }
        entries.append(.notice(id: id, section: .notice, text: notice))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? "Удалённые сообщения" : "Deleted Messages"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
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

// MARK: HolyGram: every chat with unread mentions or replies to you
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import SGItemListUI

private enum MentionsSection: Int32, SGItemListSection {
    case mentions
    case notice
}

private typealias MentionsEntry = SGItemListUIEntry<MentionsSection, AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

private struct MentionItem {
    let peer: EnginePeer
    let text: String
}

public func holyGramMentionsController(context: AccountContext) -> ViewController {
    var openChatImpl: ((EnginePeer) -> Void)?

    let mentionsSignal: Signal<[MentionItem], NoError> = combineLatest(
        context.engine.messages.chatList(group: .root, count: 1000) |> take(1),
        context.engine.messages.chatList(group: .archive, count: 1000) |> take(1)
    )
    |> map { root, archive -> [MentionItem] in
        var result: [MentionItem] = []
        for item in root.items + archive.items {
            guard item.hasUnseenMentions || item.hasUnseenReactions, let peer = item.renderedPeer.peer else {
                continue
            }
            var parts: [String] = []
            if item.hasUnseenMentions {
                parts.append("@")
            }
            if item.hasUnseenReactions {
                parts.append("❤️")
            }
            result.append(MentionItem(peer: peer, text: parts.joined(separator: " ")))
        }
        return result
    }

    var peersById: [EnginePeer.Id: EnginePeer] = [:]
    let arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, action: { action in
        guard let peerId = action.base as? EnginePeer.Id, let peer = peersById[peerId] else {
            return
        }
        openChatImpl?(peer)
    })

    let signal = combineLatest(context.sharedContext.presentationData, mentionsSignal)
    |> map { presentationData, mentions -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
        var entries: [MentionsEntry] = []
        var id = 0
        for mention in mentions {
            peersById[mention.peer.id] = mention.peer
            let title = mention.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            entries.append(.action(id: id, section: .mentions, actionType: AnyHashable(mention.peer.id), text: "\(mention.text)  \(title)", kind: .generic))
            id += 1
        }
        entries.append(.notice(id: id, section: .notice, text: mentions.isEmpty
            ? (ru ? "Непрочитанных упоминаний и реакций нет." : "No unread mentions or reactions.")
            : (ru ? "@ — вас упомянули или ответили вам, ❤️ — реакции на ваши сообщения. В чате нажмите @ внизу справа, чтобы перейти к упоминанию." : "@ — you were mentioned or replied to, ❤️ — reactions to your messages. In the chat, tap @ at the bottom right to jump to it.")))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? "Упоминания" : "Mentions"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    openChatImpl = { [weak controller] peer in
        guard let navigationController = controller?.navigationController as? NavigationController else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
    }
    return controller
}

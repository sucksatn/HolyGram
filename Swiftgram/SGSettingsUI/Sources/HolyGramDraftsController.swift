// MARK: HolyGram: every chat with an unsent draft in one place
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import SGItemListUI

private enum DraftsSection: Int32, SGItemListSection {
    case drafts
    case notice
}

private typealias DraftsEntry = SGItemListUIEntry<DraftsSection, AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

private struct DraftItem {
    let peer: EnginePeer
    let text: String
}

public func holyGramDraftsController(context: AccountContext) -> ViewController {
    var openChatImpl: ((EnginePeer) -> Void)?

    let draftsSignal: Signal<[DraftItem], NoError> = combineLatest(
        context.engine.messages.chatList(group: .root, count: 1000) |> take(1),
        context.engine.messages.chatList(group: .archive, count: 1000) |> take(1)
    )
    |> map { root, archive -> [DraftItem] in
        var result: [DraftItem] = []
        for item in root.items + archive.items {
            guard let draft = item.draft, !draft.text.isEmpty, let peer = item.renderedPeer.peer else {
                continue
            }
            result.append(DraftItem(peer: peer, text: draft.text))
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

    let signal = combineLatest(context.sharedContext.presentationData, draftsSignal)
    |> map { presentationData, drafts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
        var entries: [DraftsEntry] = []
        var id = 0
        for draft in drafts {
            peersById[draft.peer.id] = draft.peer
            let title = draft.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            let preview = String(draft.text.replacingOccurrences(of: "\n", with: " ").prefix(160))
            entries.append(.action(id: id, section: .drafts, actionType: AnyHashable(draft.peer.id), text: "\(title)\n\(preview)", kind: .generic))
            id += 1
        }
        entries.append(.notice(id: id, section: .notice, text: drafts.isEmpty
            ? (ru ? "Черновиков нет. Здесь появятся чаты, где вы начали писать и не отправили." : "No drafts. Chats where you started typing and didn't send will show up here.")
            : (ru ? "Нажмите на черновик, чтобы продолжить писать." : "Tap a draft to keep writing.")))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? "Черновики" : "Drafts"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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

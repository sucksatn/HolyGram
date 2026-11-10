// MARK: HolyGram: list of hidden chats, opened from HolyGram settings after Face ID
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

private enum HiddenChatsSection: Int32, SGItemListSection {
    case chats
    case notice
}

private typealias HiddenChatsEntry = SGItemListUIEntry<HiddenChatsSection, AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

public func holyGramHiddenChatsController(context: AccountContext) -> ViewController {
    let reload = ValuePromise(true, ignoreRepeated: false)
    var presentImpl: ((ViewController) -> Void)?
    var openChatImpl: ((EnginePeer) -> Void)?

    let peersSignal: Signal<[EnginePeer], NoError> = reload.get()
    |> mapToSignal { _ -> Signal<[EnginePeer], NoError> in
        let ids = SGSimpleSettings.shared.hiddenChats.compactMap(Int64.init).map { EnginePeer.Id($0) }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { peers -> [EnginePeer] in
            return ids.compactMap { peers[$0] ?? nil }
        }
    }

    let arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, action: { action in
        guard let peerIdValue = action.base as? Int64 else {
            return
        }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: EnginePeer.Id(peerIdValue)))
        |> deliverOnMainQueue).start(next: { peer in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            if let peer {
                items.append(ActionSheetButtonItem(title: ru ? "Открыть чат" : "Open Chat", action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    openChatImpl?(peer)
                }))
            }
            items.append(ActionSheetButtonItem(title: ru ? "Вернуть в список чатов" : "Show in Chat List", action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                SGSimpleSettings.shared.setHiddenChat(peerIdValue, false)
                reload.set(true)
            }))
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })])
            ])
            presentImpl?(actionSheet)
        })
    })

    let signal = combineLatest(context.sharedContext.presentationData, peersSignal)
    |> map { presentationData, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
        var entries: [HiddenChatsEntry] = []
        var id = 0
        if peers.isEmpty {
            entries.append(.notice(id: id, section: .notice, text: ru ? "Скрытых чатов нет. Чтобы скрыть чат, удерживайте его в списке чатов и выберите «Скрыть чат»." : "No hidden chats. To hide one, long-press it in the chat list and choose Hide Chat."))
        } else {
            for peer in peers {
                entries.append(.action(id: id, section: .chats, actionType: AnyHashable(peer.id.toInt64()), text: peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), kind: .generic))
                id += 1
            }
            entries.append(.notice(id: id, section: .notice, text: ru ? "Скрытые чаты не видны в списке чатов и при пересылке. Новые сообщения в них по-прежнему приходят." : "Hidden chats don't appear in the chat list or when forwarding. New messages still arrive."))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? "Скрытые чаты" : "Hidden Chats"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    openChatImpl = { [weak controller] peer in
        guard let navigationController = controller?.navigationController as? NavigationController else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
    }
    return controller
}

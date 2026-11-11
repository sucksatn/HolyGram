// MARK: HolyGram: contacts who haven't added the account back
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import SGItemListUI

private enum NonMutualSection: Int32, SGItemListSection {
    case contacts
    case notice
}

private typealias NonMutualEntry = SGItemListUIEntry<NonMutualSection, AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

public func holyGramNonMutualContactsController(context: AccountContext) -> ViewController {
    var openChatImpl: ((EnginePeer) -> Void)?
    var peersById: [EnginePeer.Id: EnginePeer] = [:]

    let contactsSignal: Signal<[EnginePeer], NoError> = context.engine.data.get(TelegramEngine.EngineData.Item.Contacts.List(includePresences: false))
    |> map { list -> [EnginePeer] in
        return list.peers.filter { peer in
            guard case let .user(user) = peer, user.botInfo == nil else {
                return false
            }
            return !user.flags.contains(.mutualContact)
        }
    }

    let arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, action: { action in
        guard let peerId = action.base as? EnginePeer.Id, let peer = peersById[peerId] else {
            return
        }
        openChatImpl?(peer)
    })

    let signal = combineLatest(context.sharedContext.presentationData, contactsSignal)
    |> map { presentationData, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
        var entries: [NonMutualEntry] = []
        var id = 0
        let sorted = peers.map { peer in
            (peer, peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder))
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        for (peer, title) in sorted {
            peersById[peer.id] = peer
            var text = title
            if case let .user(user) = peer, let phone = user.phone, !phone.isEmpty {
                text += "\n+" + phone
            }
            entries.append(.action(id: id, section: .contacts, actionType: AnyHashable(peer.id), text: text, kind: .generic))
            id += 1
        }
        entries.append(.notice(id: id, section: .notice, text: peers.isEmpty
            ? (ru ? "Все ваши контакты добавили вас в ответ." : "All your contacts have added you back.")
            : (ru ? "Эти люди есть у вас в контактах, а вас у них нет (или они вас удалили). Всего: \(peers.count)." : "These people are in your contacts, but you aren't in theirs (or they removed you). Total: \(peers.count).")))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? "Не добавили в ответ" : "Didn't Add You Back"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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

/// A vCard file of every contact with a phone number.
func holyGramContactsVCard(_ peers: [EnginePeer]) -> (text: String, count: Int) {
    var cards: [String] = []
    for peer in peers {
        guard case let .user(user) = peer, user.botInfo == nil else {
            continue
        }
        let escape: (String) -> String = { value in
            return value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "\n", with: " ")
        }
        let first = escape(user.firstName ?? "")
        let last = escape(user.lastName ?? "")
        var card = ["BEGIN:VCARD", "VERSION:3.0", "N:\(last);\(first);;;", "FN:\(escape([user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")))"]
        if let phone = user.phone, !phone.isEmpty {
            card.append("TEL;TYPE=CELL:+\(phone)")
        }
        if let username = peer.addressName, !username.isEmpty {
            card.append("URL:https://t.me/\(username)")
        }
        card.append("END:VCARD")
        cards.append(card.joined(separator: "\r\n"))
    }
    return (cards.joined(separator: "\r\n"), cards.count)
}

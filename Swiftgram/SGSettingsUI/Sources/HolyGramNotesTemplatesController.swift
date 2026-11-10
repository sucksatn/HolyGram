// MARK: HolyGram: message templates and private chat notes
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

private enum NotesTemplatesSection: Int32, SGItemListSection {
    case actions
    case items
    case notice
}

private typealias NotesTemplatesEntry = SGItemListUIEntry<NotesTemplatesSection, AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

private func isRussian(_ presentationData: PresentationData) -> Bool {
    let code = presentationData.strings.baseLanguageCode
    return code.hasPrefix("ru") || code.hasPrefix("uk")
}

/// Asks for a line of text; `nil` text means the user cancelled.
func hgPresentTextInput(title: String, message: String?, text: String, placeholder: String, doneTitle: String, cancelTitle: String, completion: @escaping (String) -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addTextField { field in
        field.text = text
        field.placeholder = placeholder
        field.autocapitalizationType = .sentences
    }
    alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
    alert.addAction(UIAlertAction(title: doneTitle, style: .default, handler: { [weak alert] _ in
        completion(alert?.textFields?.first?.text ?? "")
    }))
    hgTopViewController()?.present(alert, animated: true)
}

public func holyGramTemplatesController(context: AccountContext) -> ViewController {
    let reload = ValuePromise(0, ignoreRepeated: false)
    var reloadCount = 0
    let triggerReload = {
        reloadCount += 1
        reload.set(reloadCount)
    }
    var presentImpl: ((ViewController) -> Void)?

    let arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, action: { action in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = isRussian(presentationData)
        if action == AnyHashable("add") {
            guard SGSimpleSettings.shared.hgPro else {
                return
            }
            hgPresentTextInput(title: ru ? "Новый шаблон" : "New Template", message: ru ? "Шаблон можно отправить из меню сообщения → «Шаблоны»." : "Send it from a message's menu → Templates.", text: "", placeholder: ru ? "Текст шаблона" : "Template text", doneTitle: ru ? "Сохранить" : "Save", cancelTitle: presentationData.strings.Common_Cancel, completion: { text in
                HolyGramTemplates.add(text)
                triggerReload()
            })
            return
        }
        guard let template = action.base as? String else {
            return
        }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: String(template.prefix(300)), parseMarkdown: false),
                ActionSheetButtonItem(title: ru ? "Скопировать" : "Copy", action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    UIPasteboard.general.string = template
                }),
                ActionSheetButtonItem(title: presentationData.strings.Common_Delete, color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    HolyGramTemplates.remove(template)
                    triggerReload()
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })])
        ])
        presentImpl?(actionSheet)
    })

    let signal = combineLatest(context.sharedContext.presentationData, reload.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = isRussian(presentationData)
        let hasPro = SGSimpleSettings.shared.hgPro
        let templates = HolyGramTemplates.all()
        var entries: [NotesTemplatesEntry] = []
        var id = 0
        entries.append(.action(id: id, section: .actions, actionType: AnyHashable("add"), text: (ru ? "➕  Добавить шаблон" : "➕  Add Template") + (hasPro ? "" : " 🔒"), kind: .generic))
        id += 1
        for template in templates.reversed() {
            entries.append(.action(id: id, section: .items, actionType: AnyHashable(template), text: String(template.replacingOccurrences(of: "\n", with: " ").prefix(200)), kind: .generic))
            id += 1
        }
        let notice: String
        if !hasPro {
            notice = ru ? "Шаблоны работают с HolyGram Pro." : "Templates need HolyGram Pro."
        } else if templates.isEmpty {
            notice = ru ? "Шаблонов нет. Добавьте здесь или удерживайте своё сообщение → «Шаблоны» → «Сохранить как шаблон»." : "No templates. Add one here, or long-press a message → Templates → Save as Template."
        } else {
            notice = ru ? "Отправить шаблон: удерживайте любое сообщение в чате → «Шаблоны». До \(HolyGramTemplates.maxCount) шаблонов." : "To send one, long-press any message in a chat → Templates. Up to \(HolyGramTemplates.maxCount) templates."
        }
        entries.append(.notice(id: id, section: .notice, text: notice))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? "Шаблоны" : "Templates"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

public func holyGramNotesController(context: AccountContext) -> ViewController {
    let reload = ValuePromise(0, ignoreRepeated: false)
    var reloadCount = 0
    let triggerReload = {
        reloadCount += 1
        reload.set(reloadCount)
    }
    var presentImpl: ((ViewController) -> Void)?
    var openChatImpl: ((EnginePeer) -> Void)?

    let notesSignal: Signal<[(EnginePeer, String)], NoError> = reload.get()
    |> mapToSignal { _ -> Signal<[(EnginePeer, String)], NoError> in
        let notes = HolyGramNotes.all()
        let ids = notes.map { EnginePeer.Id($0.peerId) }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { peers -> [(EnginePeer, String)] in
            return notes.compactMap { note -> (EnginePeer, String)? in
                guard let peer = peers[EnginePeer.Id(note.peerId)] ?? nil else {
                    return nil
                }
                return (peer, note.text)
            }
        }
    }

    let arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(context: context, action: { action in
        guard let peerIdValue = action.base as? Int64 else {
            return
        }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: EnginePeer.Id(peerIdValue)))
        |> deliverOnMainQueue).start(next: { peer in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let ru = isRussian(presentationData)
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            if let peer {
                items.append(ActionSheetButtonItem(title: ru ? "Открыть чат" : "Open Chat", action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    openChatImpl?(peer)
                }))
            }
            items.append(ActionSheetButtonItem(title: ru ? "Изменить заметку" : "Edit Note", action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                hgPresentTextInput(title: ru ? "Заметка о чате" : "Chat Note", message: nil, text: HolyGramNotes.note(peerId: peerIdValue) ?? "", placeholder: ru ? "Видна только вам" : "Only you can see it", doneTitle: ru ? "Сохранить" : "Save", cancelTitle: presentationData.strings.Common_Cancel, completion: { text in
                    HolyGramNotes.setNote(peerId: peerIdValue, text: text)
                    triggerReload()
                })
            }))
            items.append(ActionSheetButtonItem(title: presentationData.strings.Common_Delete, color: .destructive, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                HolyGramNotes.setNote(peerId: peerIdValue, text: "")
                triggerReload()
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

    let signal = combineLatest(context.sharedContext.presentationData, notesSignal)
    |> map { presentationData, notes -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = isRussian(presentationData)
        var entries: [NotesTemplatesEntry] = []
        var id = 0
        let sorted = notes.map { peer, text in
            (peer, peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), text)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        for (peer, title, text) in sorted {
            entries.append(.action(id: id, section: .items, actionType: AnyHashable(peer.id.toInt64()), text: "\(title)\n\(String(text.replacingOccurrences(of: "\n", with: " ").prefix(200)))", kind: .generic))
            id += 1
        }
        entries.append(.notice(id: id, section: .notice, text: notes.isEmpty
            ? (ru ? "Заметок нет. Удерживайте чат в списке → «Заметка о чате». Заметки хранятся только на этом устройстве." : "No notes. Long-press a chat in the list → Chat Note. Notes stay on this device.")
            : (ru ? "Заметки видны только вам и хранятся только на этом устройстве." : "Only you can see notes; they stay on this device.")))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? "Заметки о чатах" : "Chat Notes"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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

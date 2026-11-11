import SGSimpleSettings
import SGStrings
import CountrySelectionUI
import Foundation
import UIKit
import AccountContext
import TelegramPresentationData
import TelegramCore
import TelegramStringFormatting

func sgPeerInfoProfileItems(nearestChatParticipant: (String?, Int32?), data: PeerInfoScreenData, context: AccountContext, presentationData: PresentationData, interaction: PeerInfoInteraction, isMyProfile: Bool) -> [PeerInfoScreenItem] {
    var items: [PeerInfoScreenItem] = []
    var itemId = 0
    var idText = ""
    var isMutualContact = false

    if case let .user(user) = data.peer {
        idText = String(user.id.id._internalGetInt64Value())
        isMutualContact = user.flags.contains(.mutualContact)
    } else if case let .channel(channel) = data.peer {
        idText = "-100" + String(channel.id.id._internalGetInt64Value())
    } else if case let .legacyGroup(group) = data.peer {
        idText = String(group.id.id._internalGetInt64Value())
    }

    if SGSimpleSettings.shared.showProfileId {
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: "id: \(idText)", text: "", textColor: .primary, action: nil, longTapAction: { sourceNode in
            interaction.openPeerInfoContextMenu(.copy(idText), sourceNode, nil)
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
        itemId += 1
    }

    if SGSimpleSettings.shared.showDC {
        var dcId: Int? = nil
        var phoneCountryText = ""
        var dcLabel = ""
        var dcText = ""

        if let cachedData = data.cachedData as? CachedUserData, let phoneCountry = cachedData.peerStatusSettings?.phoneCountry {
            var countryName = ""
            let countriesConfiguration = context.currentCountriesConfiguration.with { $0 }
            if let country = countriesConfiguration.countries.first(where: { $0.id == phoneCountry }) {
                countryName = country.localizedName ?? country.name
            } else if phoneCountry == "FT" {
                countryName = presentationData.strings.Chat_NonContactUser_AnonymousNumber
            } else if phoneCountry == "TS" {
                countryName = "Test"
            }
            phoneCountryText = emojiFlagForISOCountryCode(phoneCountry) + " " + countryName
        }
        if let peer = data.peer, let smallProfileImage = peer.smallProfileImage, let cloudResource = smallProfileImage.resource as? CloudPeerPhotoSizeMediaResource {
            dcId = cloudResource.datacenterId
        }

        if let dcId = dcId {
            dcLabel = "dc: \(dcId)"
            if !phoneCountryText.isEmpty {
                dcText = phoneCountryText
            }
        } else if !phoneCountryText.isEmpty {
            dcLabel = "dc: ?"
            dcText = phoneCountryText
        }

        if !dcText.isEmpty || !dcLabel.isEmpty {
            items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: dcLabel, text: dcText, textColor: .primary, action: nil, longTapAction: { sourceNode in
                interaction.openPeerInfoContextMenu(.aboutDC, sourceNode, nil)
            }, requestLayout: { _ in
                interaction.requestLayout(false)
            }))
            itemId += 1
        }
    }

    if SGSimpleSettings.shared.showCreationDate, let channelCreationTimestamp = data.channelCreationTimestamp {
        let creationDateString = stringForDate(timestamp: channelCreationTimestamp, strings: presentationData.strings)
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: i18n("Chat.Created", presentationData.strings.baseLanguageCode, creationDateString), text: "", action: nil, longTapAction: { sourceNode in
            interaction.openPeerInfoContextMenu(.copy(creationDateString), sourceNode, nil)
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
        itemId += 1
    }

    if let invitedAt = nearestChatParticipant.1 {
        let joinedDateString = stringForDate(timestamp: invitedAt, strings: presentationData.strings)
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: i18n("Chat.JoinedDateTitle", presentationData.strings.baseLanguageCode, nearestChatParticipant.0 ?? "chat"), text: joinedDateString, action: nil, longTapAction: { sourceNode in
            interaction.openPeerInfoContextMenu(.copy(joinedDateString), sourceNode, nil)
        }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
        itemId += 1
    }

    if SGSimpleSettings.shared.showRegDate {
        var regDateString = ""
        if let cachedData = data.cachedData as? CachedUserData, let registrationDate = cachedData.peerStatusSettings?.registrationDate {
            let components = registrationDate.components(separatedBy: ".")
            if components.count == 2, let first = Int32(components[0]), let second = Int32(components[1]) {
                let month = first - 1
                let year = second - 1900
                regDateString = stringForMonth(strings: presentationData.strings, month: month, ofYear: year)
            }
        }
        if let regDate = data.regDate, regDateString.isEmpty {
            let regTimestamp = Int32((regDate.from + regDate.to) / 2)
            switch context.currentAppConfiguration.with({ $0 }).sgWebSettings.global.regdateFormat {
                case "year":
                    regDateString = stringForDateWithoutDayAndMonth(date: Date(timeIntervalSince1970: Double(regTimestamp)), strings: presentationData.strings)
                case "month":
                    regDateString = stringForDateWithoutDay(date: Date(timeIntervalSince1970: Double(regTimestamp)), strings: presentationData.strings)
                default:
                    regDateString = stringForDate(timestamp: regTimestamp, strings: presentationData.strings)
            }
        }
        if !regDateString.isEmpty {
            items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: i18n("Chat.RegDate", presentationData.strings.baseLanguageCode), text: regDateString, action: nil, longTapAction: { sourceNode in
                interaction.openPeerInfoContextMenu(.copy(regDateString), sourceNode, nil)
            }, requestLayout: { _ in
                interaction.requestLayout(false)
            }))
            itemId += 1
        }
    }
    if isMutualContact && !isMyProfile {
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: i18n("MutualContact.Label", presentationData.strings.baseLanguageCode), text: "", action: nil, longTapAction: { _ in }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
        itemId += 1
    }

    // MARK: HolyGram: a contact who hasn't added you back, and your private note about the chat
    let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru") || presentationData.strings.baseLanguageCode.hasPrefix("uk")
    if SGSimpleSettings.shared.hgPro, !isMyProfile, case let .user(user) = data.peer, user.botInfo == nil, data.isContact, !isMutualContact {
        items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: ru ? "💔 Не добавил(а) вас в контакты" : "💔 Hasn't added you back", text: "", action: nil, longTapAction: { _ in }, requestLayout: { _ in
            interaction.requestLayout(false)
        }))
        itemId += 1
    }
    if SGSimpleSettings.shared.profileNote && SGSimpleSettings.shared.hgPro && !isMyProfile, let peerId = data.peer?.id {
        let peerIdValue = peerId.toInt64()
        let note = HolyGramNotes.note(peerId: peerIdValue)
        let edit: () -> Void = {
            guard var presenter = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else {
                return
            }
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            let alert = UIAlertController(title: ru ? "Заметка" : "Note", message: ru ? "Видна только вам и хранится на этом устройстве." : "Only you can see it; it stays on this device.", preferredStyle: .alert)
            alert.addTextField { field in
                field.text = HolyGramNotes.note(peerId: peerIdValue)
                field.placeholder = ru ? "Текст заметки" : "Note text"
                field.autocapitalizationType = .sentences
            }
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: ru ? "Сохранить" : "Save", style: .default, handler: { [weak alert] _ in
                HolyGramNotes.setNote(peerId: peerIdValue, text: alert?.textFields?.first?.text ?? "")
                interaction.requestLayout(true)
            }))
            presenter.present(alert, animated: true)
        }
        if let note {
            items.append(PeerInfoScreenLabeledValueItem(id: itemId, label: ru ? "📒 Заметка (нажмите, чтобы изменить)" : "📒 Note (tap to edit)", text: note, textColor: .primary, action: { _, _ in
                edit()
            }, longTapAction: { sourceNode in
                interaction.openPeerInfoContextMenu(.copy(note), sourceNode, nil)
            }, requestLayout: { _ in
                interaction.requestLayout(false)
            }))
        } else {
            items.append(PeerInfoScreenActionItem(id: itemId, text: ru ? "📒 Добавить заметку" : "📒 Add Note", color: .accent, action: {
                edit()
            }))
        }
        itemId += 1
    }

    return items
}

func sgPeerInfoSettingsProfileIdItems(data: PeerInfoScreenData, interaction: PeerInfoInteraction) -> [PeerInfoScreenItem] {
    guard SGSimpleSettings.shared.showProfileId else {
        return []
    }

    let idText = data.peer.map { String($0.id.id._internalGetInt64Value()) } ?? ""
    return [PeerInfoScreenActionItem(id: 100, text: "ID: \(idText)", color: .accent, action: {
        UIPasteboard.general.string = idText
        interaction.notifyTextCopied()
    })]
}

func sgPeerInfoSettingsItems(context: AccountContext, paymentsEnabled: Bool, presentationData: PresentationData, interaction: PeerInfoInteraction) -> [PeerInfoScreenItem] {
    let hasNewFeatures = {
        return false
    }
    let swiftgramLabel: PeerInfoScreenDisclosureItem.Label
    if hasNewFeatures() {
        swiftgramLabel = .titleBadge(presentationData.strings.Settings_New, presentationData.theme.list.itemAccentColor)
    } else {
        swiftgramLabel = .none
    }

    let hasNewProFeatures = {
        return false
    }
    let swiftgramProLabel: PeerInfoScreenDisclosureItem.Label
    if hasNewProFeatures() {
        swiftgramProLabel = .titleBadge(presentationData.strings.Settings_New, presentationData.theme.list.itemAccentColor)
    } else {
        swiftgramProLabel = .none
    }

    var items: [PeerInfoScreenItem] = []
    if paymentsEnabled || context.sharedContext.immediateSGStatus.status > 1 {
        items.append(PeerInfoScreenDisclosureItem(id: 0, label: swiftgramProLabel, text: "HolyGram Pro", icon: PresentationResourcesSettings.swiftgramPro, action: {
            interaction.openSettings(.swiftgramPro)
        }))
    }
    items.append(PeerInfoScreenDisclosureItem(id: 1, label: swiftgramLabel, text: "HolyGram", icon: PresentationResourcesSettings.swiftgram, action: {
        interaction.openSettings(.swiftgram)
    }))
    return items
}

// MARK: HolyGram
import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import SGSimpleSettings

private func holyGramStoreMessage(_ message: Message, attributes: [MessageAttribute]) -> StoreMessage {
    return StoreMessage(
        id: message.id,
        customStableId: nil,
        globallyUniqueId: message.globallyUniqueId,
        groupingKey: message.groupingKey,
        threadId: message.threadId,
        timestamp: message.timestamp,
        flags: StoreMessageFlags(message.flags),
        tags: message.tags,
        globalTags: message.globalTags,
        localTags: message.localTags,
        forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init),
        authorId: message.author?.id,
        text: message.text,
        attributes: attributes,
        media: message.media
    )
}

/// Instead of deleting cloud messages the server says were deleted, marks them
/// with `HolyGramDeletedMessageAttribute`. Returns the ids that should still be deleted.
func holyGramKeepDeletedMessages(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    guard SGSimpleSettings.shared.hgSaveDeletedMessages else {
        return ids
    }
    let now = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
    var remaining: [MessageId] = []
    for id in ids {
        // Scheduled, quick-reply and local messages are removed for other reasons (sent, edited, ...).
        guard id.namespace == Namespaces.Message.Cloud, let message = transaction.getMessage(id) else {
            remaining.append(id)
            continue
        }
        if message.holyGramDeletedAttribute != nil {
            continue
        }
        transaction.updateMessage(id, update: { current in
            var attributes = current.attributes
            attributes.append(HolyGramDeletedMessageAttribute(date: now))
            return .update(holyGramStoreMessage(current, attributes: attributes))
        })
        HolyGramDeletedIndex.add(peerId: id.peerId.toInt64(), namespace: id.namespace, id: id.id, deletedAt: now)
    }
    return remaining
}

/// Same as above for deletions addressed by global message id (private chats and basic groups).
func holyGramKeepDeletedMessages(transaction: Transaction, globalIds: [Int32]) -> [Int32] {
    guard SGSimpleSettings.shared.hgSaveDeletedMessages else {
        return globalIds
    }
    var remaining: [Int32] = []
    for globalId in globalIds {
        guard let id = transaction.messageIdsForGlobalIds([globalId]).first else {
            remaining.append(globalId)
            continue
        }
        if !holyGramKeepDeletedMessages(transaction: transaction, ids: [id]).isEmpty {
            remaining.append(globalId)
        }
    }
    return remaining
}

/// Adds the text being replaced to the message's edit history.
func holyGramMessageWithEditHistory(previous: Message, updated: StoreMessage) -> StoreMessage {
    guard SGSimpleSettings.shared.hgSaveEditHistory else {
        return updated
    }
    // Edit updates also arrive for reactions, views and similar; only text changes count.
    if previous.text == updated.text || previous.text.isEmpty {
        return updated
    }
    var entries = previous.holyGramEditHistory
    let previousDate = previous.editedTime ?? previous.timestamp
    if entries.last?.text != previous.text {
        entries.append(HolyGramEditHistoryMessageAttribute.Entry(text: previous.text, date: previousDate))
    }
    var attributes = updated.attributes.filter { !($0 is HolyGramEditHistoryMessageAttribute) }
    attributes.append(HolyGramEditHistoryMessageAttribute(entries: entries))
    return updated.withUpdatedAttributes(attributes)
}

// MARK: HolyGram ghost mode: after sending

/// Telegram marks the account online when it sends a message. In ghost mode, go back
/// offline right away, and optionally send the read receipt for the chat replied to.
func holyGramAfterMessageSent(postbox: Postbox, network: Network, stateManager: AccountStateManager, peerId: PeerId) {
    let settings = SGSimpleSettings.shared
    if settings.ghostBlocksOnline {
        let _ = network.request(Api.functions.account.updateStatus(offline: .boolTrue)).start()
    }
    if settings.ghostBlocksReadReceipts && settings.ghostReadOnReply {
        let _ = (postbox.transaction { transaction -> (Peer, MessageId.Id)? in
            guard let peer = transaction.getPeer(peerId), let readStates = transaction.getPeerReadStates(peerId) else {
                return nil
            }
            for (namespace, readState) in readStates where namespace == Namespaces.Message.Cloud {
                if case let .idBased(maxIncomingReadId, _, _, _, _) = readState, maxIncomingReadId > 0 {
                    return (peer, maxIncomingReadId)
                }
            }
            return nil
        }
        |> mapToSignal { value -> Signal<Never, NoError> in
            guard let (peer, maxId) = value else {
                return .complete()
            }
            if let channel = peer as? TelegramChannel, let inputChannel = apiInputChannel(channel) {
                return network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: maxId))
                |> `catch` { _ -> Signal<Api.Bool, NoError> in
                    return .complete()
                }
                |> ignoreValues
            } else if let inputPeer = apiInputPeer(peer), peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup {
                return network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: maxId))
                |> map(Optional.init)
                |> `catch` { _ -> Signal<Api.messages.AffectedMessages?, NoError> in
                    return .single(nil)
                }
                |> mapToSignal { result -> Signal<Never, NoError> in
                    if let result, case let .affectedMessages(data) = result {
                        stateManager.addUpdateGroups([.updatePts(pts: data.pts, ptsCount: data.ptsCount)])
                    }
                    return .complete()
                }
            } else {
                return .complete()
            }
        }).start()
    }
}

/// MARK: HolyGram: the notification service deletes messages when a push says they were deleted,
/// even while the app is closed. Keep them the same way the app does.
public func holyGramDeleteMessagesFromPush(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
    let remaining = holyGramKeepDeletedMessages(transaction: transaction, ids: ids)
    if !remaining.isEmpty {
        _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: remaining, deleteMedia: true)
    }
}

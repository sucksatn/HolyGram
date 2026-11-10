// MARK: HolyGram
import Foundation
import Postbox
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
    guard SGSimpleSettings.shared.saveDeletedMessages else {
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
    }
    return remaining
}

/// Same as above for deletions addressed by global message id (private chats and basic groups).
func holyGramKeepDeletedMessages(transaction: Transaction, globalIds: [Int32]) -> [Int32] {
    guard SGSimpleSettings.shared.saveDeletedMessages else {
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
    guard SGSimpleSettings.shared.saveEditHistory else {
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

// MARK: HolyGram
import Foundation
import Postbox

/// Marks a message that was deleted on the server but kept on this device.
public final class HolyGramDeletedMessageAttribute: MessageAttribute {
    /// When the deletion arrived.
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

/// Earlier versions of a message's text, oldest first.
public final class HolyGramEditHistoryMessageAttribute: MessageAttribute {
    public struct Entry: Equatable {
        public let text: String
        /// When this version was posted (the send date, or the date of the edit that produced it).
        public let date: Int32

        public init(text: String, date: Int32) {
            self.text = text
            self.date = date
        }
    }

    /// Keep the attribute bounded on messages that get edited many times.
    public static let maxEntries = 50

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = Array(entries.suffix(HolyGramEditHistoryMessageAttribute.maxEntries))
    }

    required public init(decoder: PostboxDecoder) {
        let texts = decoder.decodeStringArrayForKey("t")
        let dates = decoder.decodeInt32ArrayForKey("d")
        var entries: [Entry] = []
        for i in 0 ..< min(texts.count, dates.count) {
            entries.append(Entry(text: texts[i], date: dates[i]))
        }
        self.entries = entries
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeStringArray(self.entries.map(\.text), forKey: "t")
        encoder.encodeInt32Array(self.entries.map(\.date), forKey: "d")
    }
}

public extension Message {
    var holyGramDeletedAttribute: HolyGramDeletedMessageAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? HolyGramDeletedMessageAttribute {
                return attribute
            }
        }
        return nil
    }

    var holyGramEditHistory: [HolyGramEditHistoryMessageAttribute.Entry] {
        for attribute in self.attributes {
            if let attribute = attribute as? HolyGramEditHistoryMessageAttribute {
                return attribute.entries
            }
        }
        return []
    }
}

/// Server updates replace a message's attributes; carry the HolyGram ones over.
func holyGramMergeMessageAttributes(previous: [MessageAttribute], updated: inout [MessageAttribute]) {
    for attribute in previous {
        if attribute is HolyGramDeletedMessageAttribute || attribute is HolyGramEditHistoryMessageAttribute {
            let type = type(of: attribute)
            if !updated.contains(where: { Swift.type(of: $0) == type }) {
                updated.append(attribute)
            }
        }
    }
}

import Foundation
import SwiftUI
import SeeleseekCore

/// Builds display text for chat messages. URLs become links. A `/me`
/// message becomes a "* username action" line.
@MainActor
enum ChatMessageFormatter {
    private static var cache: [UUID: AttributedString] = [:]
    private static var linkCache: [UUID: [URL]] = [:]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func isAction(_ message: ChatMessage) -> Bool {
        message.content.hasPrefix("/me ")
    }

    static func attributed(for message: ChatMessage) -> AttributedString {
        if let cached = cache[message.id] {
            return cached
        }
        let display: String
        if isAction(message) {
            display = "* \(message.username) \(message.content.dropFirst(4))"
        } else {
            display = message.content
        }
        let result = linkified(display)
        // Limit the cache size.
        if cache.count > 2000 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[message.id] = result
        return result
    }

    /// URLs found in the message content. Rotor "Open link" actions
    /// use this list because VoiceOver cannot activate inline links
    /// inside a combined bubble element.
    static func links(in message: ChatMessage) -> [URL] {
        if let cached = linkCache[message.id] {
            return cached
        }
        let content = message.content
        var found: [URL] = []
        if content.contains("://") || content.contains("www."), let detector = linkDetector {
            let fullRange = NSRange(content.startIndex..., in: content)
            found = detector.matches(in: content, options: [], range: fullRange).compactMap(\.url)
        }
        if linkCache.count > 2000 {
            linkCache.removeAll(keepingCapacity: true)
        }
        linkCache[message.id] = found
        return found
    }

    private static func linkified(_ content: String) -> AttributedString {
        var attributed = AttributedString(content)
        guard content.contains("://") || content.contains("www."),
              let detector = linkDetector
        else {
            return attributed
        }
        let fullRange = NSRange(content.startIndex..., in: content)
        for match in detector.matches(in: content, options: [], range: fullRange) {
            guard let url = match.url,
                  let range = Range(match.range, in: attributed)
            else { continue }
            attributed[range].link = url
            attributed[range].underlineStyle = .single
        }
        return attributed
    }
}

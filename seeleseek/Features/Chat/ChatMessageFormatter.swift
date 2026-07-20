import Foundation
import SwiftUI
import SeeleseekCore

/// Builds display text for chat messages: URLs become tappable links and
/// `/me` messages render as "* username action" lines.
@MainActor
enum ChatMessageFormatter {
    private static var cache: [UUID: AttributedString] = [:]

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
        // Bound the cache; entries are tiny but rooms are long-lived.
        if cache.count > 2000 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[message.id] = result
        return result
    }

    private static func linkified(_ content: String) -> AttributedString {
        var attributed = AttributedString(content)
        guard content.contains("://") || content.contains("www."),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
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

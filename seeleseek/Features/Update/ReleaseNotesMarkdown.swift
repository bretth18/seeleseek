import Foundation

/// GitHub release bodies are headings and bullet lists, which SwiftUI's
/// inline-only markdown drops. Blocks are split here; inline syntax
/// (bold, code, links) is left to `AttributedString(markdown:)`.
enum ReleaseNotesMarkdown {
    enum Block: Equatable {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let heading = stripped(line, marker: "#", maxCount: 6) {
                flush()
                blocks.append(.heading(heading))
            } else if let bullet = ["*", "-", "+"].lazy.compactMap({ stripped(line, marker: $0, maxCount: 1) }).first {
                flush()
                blocks.append(.bullet(bullet))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// "## Title" → "Title". The marker run must be followed by a space,
    /// so "**bold**" and "---" are not mistaken for list items.
    private static func stripped(_ line: String, marker: Character, maxCount: Int) -> String? {
        let markers = line.prefix { $0 == marker }
        guard (1...maxCount).contains(markers.count) else { return nil }
        let rest = line.dropFirst(markers.count)
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    static func inline(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        shortenGitHubLinks(&attributed)
        return attributed
    }

    /// The parser autolinks bare URLs. GitHub shows its own PR and issue
    /// links as "#123", so bare ones are shortened to match; `[text](url)`
    /// links keep their text.
    private static func shortenGitHubLinks(_ attributed: inout AttributedString) {
        let bare = attributed.runs.compactMap { run -> (Range<AttributedString.Index>, URL, String)? in
            guard let url = run.link, let label = shortLabel(for: url),
                  String(attributed[run.range].characters) == url.absoluteString
            else { return nil }
            return (run.range, url, label)
        }
        for (range, url, label) in bare.reversed() {
            var link = AttributedString(label)
            link.link = url
            attributed.replaceSubrange(range, with: link)
        }
    }

    static func shortLabel(for url: URL) -> String? {
        let parts = url.pathComponents
        guard url.host == "github.com", parts.count == 5,
              parts[3] == "pull" || parts[3] == "issues", Int(parts[4]) != nil
        else { return nil }
        return "#\(parts[4])"
    }
}

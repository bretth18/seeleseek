import SwiftUI
import SeeleseekCore

/// Folder glyph + path in tertiary mono. Middle-truncates so the leaf
/// folder — the part that identifies the release — survives at any width.
struct FolderPathLabel: View {
    let text: String
    /// Full, un-elided path for the tooltip. Defaults to `text`.
    var help: String?

    init(_ text: String, help: String? = nil) {
        self.text = text
        self.help = help
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: "folder")
                .font(.system(size: SeeleSpacing.iconSizeXS))
                .foregroundStyle(SeeleColors.textTertiary)
                .accessibilityHidden(true)

            Text(text)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .rowHelp(help ?? text)
        }
    }
}

extension FolderPathLabel {
    /// Keeps up to the last three components of a backslash-separated
    /// SoulSeek path; earlier components collapse to `…`.
    static func compact(_ path: String) -> String {
        let parts = path.split(separator: "\\").map(String.init)
        guard !parts.isEmpty else { return "" }
        if parts.count <= 3 {
            return parts.joined(separator: "/")
        }
        return "…/" + parts.suffix(3).joined(separator: "/")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
        FolderPathLabel("Music/Albums/Selected Ambient Works")
        FolderPathLabel(
            FolderPathLabel.compact("Shared\\Music\\FLAC\\Aphex Twin\\SAW 85-92"),
            help: "Shared/Music/FLAC/Aphex Twin/SAW 85-92"
        )
    }
    .padding()
    .background(SeeleColors.background)
}

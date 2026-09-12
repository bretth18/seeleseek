import SwiftUI

/// Renders a GitHub release body: headings, bullets, paragraphs, with
/// inline bold/code/links. `compact` is the caption-sized variant for
/// the settings card.
struct ReleaseNotesView: View {
    private let blocks: [ReleaseNotesMarkdown.Block]
    private let compact: Bool

    init(markdown: String, compact: Bool = false) {
        blocks = ReleaseNotesMarkdown.blocks(markdown)
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? SeeleSpacing.xs : SeeleSpacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .heading(let text):
                    Text(ReleaseNotesMarkdown.inline(text))
                        .font(compact ? SeeleTypography.statusText : SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)
                        .padding(.top, index == 0 ? 0 : SeeleSpacing.xs)
                        .accessibilityAddTraits(.isHeader)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: SeeleSpacing.sm) {
                        Text("•")
                            .foregroundStyle(SeeleColors.textTertiary)
                            .accessibilityHidden(true)
                        Text(ReleaseNotesMarkdown.inline(text))
                    }
                case .paragraph(let text):
                    Text(ReleaseNotesMarkdown.inline(text))
                }
            }
        }
        .font(compact ? SeeleTypography.caption : SeeleTypography.body)
        .foregroundStyle(compact ? SeeleColors.textSecondary : SeeleColors.textPrimary)
        .tint(SeeleColors.accent)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

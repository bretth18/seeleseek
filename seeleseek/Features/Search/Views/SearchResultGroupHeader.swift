import SwiftUI
import SeeleseekCore

/// Folder header for a grouped search result.
///
/// Built from the same pieces as `SearchResultRow` rather than hand-rolled
/// chrome: `StandardListRow` for padding, hover and Reduce Motion, `RowGlyph`
/// for the leading badge, `RowLayout`/`SearchResultRowLayout` for the column
/// anchors. What marks it as a folder is the amber glyph and the medium-weight
/// title — not a bespoke background, which would read as a different kind of
/// surface than the list it belongs to.
struct SearchResultGroupHeader: View {
    @Environment(\.appState) private var appState

    let group: SearchResultGroup
    let isExpanded: Bool
    let onToggleExpansion: () -> Void

    @State private var isHovered = false

    private var searchState: SearchState { appState.searchState }

    var body: some View {
        StandardListRow(onHoverChanged: { isHovered = $0 }) {
            HStack(alignment: .center, spacing: SeeleSpacing.sm) {
                if searchState.isSelectionMode {
                    SearchGroupSelectionToggle(group: group)
                }

                folderGlyph

                infoColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                SearchGroupDownloadButton(group: group, isHovered: isHovered)
                    .frame(width: SearchResultRowLayout.trailingClusterWidth, alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpansion)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
        .accessibilityHint("Activate to \(isExpanded ? "collapse" : "expand") this folder")
        .accessibilityAction(named: isExpanded ? "Collapse" : "Expand", onToggleExpansion)
    }

    private var folderGlyph: some View {
        RowGlyph(systemName: "folder.fill", tint: SeeleColors.warning)
            .overlay(alignment: .bottomTrailing) {
                // Ternary on the value, not a branch, so the chevron keeps one
                // identity and the rotation animates.
                RowGlyphOrnament(
                    systemName: "chevron.right",
                    rotation: .degrees(isExpanded ? 90 : 0)
                )
            }
            .accessibilityHidden(true)
    }

    /// Mirrors `SearchResultRow.infoColumn`: title line, then a quieter
    /// context line, so a header and a loose row scan as the same shape.
    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            HStack(spacing: SeeleSpacing.xs) {
                Text(group.displayName)
                    .font(SeeleTypography.body.weight(.medium))
                    .foregroundStyle(SeeleColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let quality = group.commonQuality {
                    StandardMetadataBadge(quality, color: SeeleColors.success)
                }
            }

            HStack(spacing: 0) {
                PeerUsernameLabel(
                    iconName: "arrow.up",
                    username: group.username,
                    width: RowLayout.peerUsernameWidth
                )

                Text("\(group.fileCount) files · \(group.totalSize.formattedBytes)")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(group.displayName), folder from \(group.username)"]
        parts.append("\(group.fileCount) files")
        parts.append(group.totalSize.formattedBytes)
        if let quality = group.commonQuality { parts.append(quality) }
        return parts.joined(separator: ", ")
    }
}

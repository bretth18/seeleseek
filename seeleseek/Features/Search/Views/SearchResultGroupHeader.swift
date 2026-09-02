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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let group: SearchResultGroup

    private var searchState: SearchState { appState.searchState }
    private var isExpanded: Bool { searchState.isExpanded(group) }

    var body: some View {
        StandardListRow {
            HStack(alignment: .center, spacing: SeeleSpacing.sm) {
                if searchState.isSelectionMode {
                    SearchGroupSelectionToggle(group: group)
                }

                folderGlyph

                infoColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                SearchGroupDownloadButton(group: group)
                    .frame(width: SearchResultRowLayout.trailingClusterWidth, alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { searchState.toggleExpansion(group) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Activate to \(isExpanded ? "collapse" : "expand") this folder")
        // Tap gestures do not survive `.combine` on macOS: without an
        // explicit default action, VO-Space does nothing despite the hint.
        .accessibilityAction { searchState.toggleExpansion(group) }
        .accessibilityAction(named: isExpanded ? "Collapse" : "Expand") { searchState.toggleExpansion(group) }
    }

    private var folderGlyph: some View {
        RowGlyph(systemName: "folder.fill", tint: SeeleColors.warning)
            .overlay(alignment: .bottomTrailing) {
                // Ternary, not a branch, so the chevron keeps one identity
                // and the rotation can animate.
                RowGlyphOrnament(
                    systemName: "chevron.right",
                    rotation: .degrees(isExpanded ? 90 : 0)
                )
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: SeeleSpacing.animationFast),
                    value: isExpanded
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

                Text("\(group.fileCount) files · \(group.formattedTotalSize)")
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
        parts.append(group.formattedTotalSize)
        if let quality = group.commonQuality { parts.append(quality) }
        return parts.joined(separator: ", ")
    }

    /// The explicit value replaces everything `.combine` would surface, and
    /// a collapsed group renders no child rows — so in selection mode the
    /// tri-state selection must be spoken here or it is inaudible.
    private var accessibilityValue: String {
        var parts = [isExpanded ? "expanded" : "collapsed"]
        if searchState.isSelectionMode {
            parts.append(SearchGroupSelectionToggle.spokenValue(for: searchState.selectionState(of: group)))
        }
        return parts.joined(separator: ", ")
    }
}

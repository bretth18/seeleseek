import SwiftUI
#if os(macOS)
import AppKit
#endif
import SeeleseekCore

// MARK: - Row
//
// Two-tier layout split down the middle of the row:
//   Left (flex):
//     Line 1  filename
//     Line 2  ↑ user · peer-speed    📁 folder-path
//   Right (fixed-width, right-aligned):
//     Line 1  [QUALITY]  FLAC 1411   44.1/16   6:53   45 MB    [browse] [↓]
//     Line 2                                          Queue 5 / ● Available
//
// Alignment anchors:
//   - Filename truncates middle, doesn't push anything.
//   - Username lives in a fixed sub-cell so peer-speed lands at the same X
//     on every row.
//   - The peer cell as a whole is fixed-width so the folder icon lands at
//     the same X on every row.
//   - Every tech-spec column is a fixed width so the same field is at the
//     same X on every row, regardless of what's in it (`—` placeholder
//     preserves slot width).
//   - The trailing cluster is fixed-width regardless of hover so the
//     tech-spec anchors never shift.

/// Layout shell only. Every stored property is Equatable so the row is
/// skipped when its inputs are unchanged, and nothing in `body` reads an
/// observable: transfer status, ignore list, folder-request state and
/// hover are read by the leaf that renders them, so hundreds of live rows
/// do not re-body when any of those change elsewhere in the app.
struct SearchResultRow: View {
    @Environment(\.appState) private var appState
    let result: SearchResult
    /// Rows under a folder header drop the context line — the header
    /// already names the peer and folder.
    var isNestedInGroup: Bool = false
    var isSelectionMode: Bool = false
    var isSelected: Bool = false

    /// Captured on appear: reading `SocialState.peerStatuses` live would
    /// invalidate every visible row on every unrelated peer's status.
    @State private var peerStatus: BuddyStatus?

    var body: some View {
        #if DEBUG
        let _ = { if SynthDiag.logChanges { Self._printChanges() } }()
        #endif
        let actions = SearchResultActions(result: result, appState: appState)
        StandardListRow {
            HStack(alignment: .top, spacing: SeeleSpacing.sm) {
                if isSelectionMode {
                    selectionCheckbox(actions)
                }

                fileGlyph

                SearchResultInfoColumn(
                    result: result,
                    isNestedInGroup: isNestedInGroup,
                    peerStatus: peerStatus
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                SearchResultMetadataColumn(result: result)

                SearchResultActionCluster(result: result, actions: actions)
            }
        }
        // Fixed height so the lazy stack places the row without measuring
        // its content — per-row measurement was the dominant scroll cost.
        .frame(height: SearchResultRowLayout.rowHeight)
        .background(selectionOverlay)
        .contentShape(Rectangle())
        .modifier(SearchResultRowInteractions(
            actions: actions,
            isSelectionMode: isSelectionMode,
            isSelected: isSelected
        ))
        .onAppear { peerStatus = appState.socialState.peerStatus(for: result.username) }
    }

    // MARK: - Selection checkbox

    private func selectionCheckbox(_ actions: SearchResultActions) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: SeeleSpacing.iconSize))
            .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textTertiary)
            .frame(width: SeeleSpacing.iconSizeXL, height: SeeleSpacing.iconSizeXL)
            .contentShape(Rectangle())
            .onTapGesture { actions.toggleSelection() }
            // The row element exposes selection state and a rotor action.
            .accessibilityHidden(true)
    }

    // MARK: - Selection highlight

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelected {
            ZStack {
                SeeleColors.selectionBackground
                RoundedRectangle.buttonShape
                    .stroke(SeeleColors.selectionBorder, lineWidth: SeeleSpacing.strokeThin)
            }
        }
    }

    // MARK: - File glyph

    private var fileGlyph: some View {
        RowGlyph(systemName: glyphIcon, tint: glyphTint)
            .overlay(alignment: .bottomTrailing) {
                if result.isPrivate {
                    RowGlyphOrnament(systemName: "lock.fill", tint: SeeleColors.warning)
                }
            }
    }

    private var glyphIcon: String {
        if result.isLossless { return "waveform" }
        if result.isAudioFile { return "music.note" }
        if result.isImageFile { return "photo"}
        if result.isVideoFile { return "video" }
        return "doc"
    }

    private var glyphTint: Color {
        if result.isLossless { return SeeleColors.success }
        if result.isAudioFile { return SeeleColors.accent }
        return SeeleColors.textTertiary
    }
}

// MARK: - Interactions

/// Double-click, context menu and accessibility for a row. A ViewModifier's
/// body is its own invalidation scope, so the transfer-status, ignore-list
/// and folder-request reads below re-evaluate this node, not the row.
private struct SearchResultRowInteractions: ViewModifier {
    @Environment(\.appState) private var appState
    let actions: SearchResultActions
    let isSelectionMode: Bool
    let isSelected: Bool

    private var result: SearchResult { actions.result }

    func body(content: Content) -> some View {
        let status = actions.downloadStatus
        let isIgnored = actions.isIgnored
        let isQueued = actions.isQueued
        content
            .onTapGesture(count: 2) { actions.download() }
            .contextMenu { contextMenu(isQueued: isQueued, isIgnored: isIgnored) }
            // `.ignore`, not `.combine`: the row supplies its own label and
            // value, and combining would traverse the subtree per update.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(isIgnored: isIgnored))
            .accessibilityValue(accessibilityValue(status: status))
            .accessibilityAddTraits(accessibilityTraits(isQueued: isQueued))
            // The double-tap gesture does not become an AXPress action.
            .accessibilityAction { actions.download() }
            // Named actions, not `accessibilityActions { Button… }`: each
            // Button there is a live view per row.
            .accessibilityAction(named: "Download entire folder", actions.downloadContainingFolder)
            .accessibilityAction(named: "Browse folder", actions.browseFolder)
            .accessibilityAction(named: "Browse \(result.username)", actions.browseUser)
            .accessibilityAction(named: "View profile", actions.viewProfile)
            .accessibilityActions {
                if isSelectionMode {
                    Button(isSelected ? "Deselect" : "Select") { actions.toggleSelection() }
                }
            }
    }

    private func accessibilityLabel(isIgnored: Bool) -> String {
        var parts: [String] = [result.displayFilename]
        parts.append("from \(result.username)")
        parts.append(QualityScale.tier(for: result).label.lowercased())
        if let bitrate = result.formattedBitrate { parts.append(bitrate) }
        parts.append(result.formattedSize)
        if let duration = result.formattedDuration { parts.append(duration) }
        if !result.freeSlots { parts.append("queued, position \(result.queueLength)") }
        if isIgnored { parts.append("ignored user") }
        if result.isPrivate { parts.append("private file") }
        return parts.joined(separator: ", ")
    }

    private func accessibilityValue(status: Transfer.TransferStatus?) -> String {
        var parts: [String] = []
        if isSelectionMode {
            parts.append(isSelected ? "selected" : "not selected")
        }
        if status != nil {
            parts.append(actions.actionHelp)
        }
        // The row's explicit label overrides FolderRequestIndicator's own,
        // so the request state must be spoken here.
        switch appState.folderRequestState(for: result) {
        case .fetching:
            parts.append("getting folder contents")
        case .failed(let reason):
            parts.append("folder download failed, \(reason)")
        case nil:
            break
        }
        return parts.joined(separator: ", ")
    }

    private func accessibilityTraits(isQueued: Bool) -> AccessibilityTraits {
        var traits: AccessibilityTraits = []
        if !isQueued {
            traits.insert(.isButton)
        }
        if isSelectionMode && isSelected {
            traits.insert(.isSelected)
        }
        return traits
    }

    @ViewBuilder
    private func contextMenu(isQueued: Bool, isIgnored: Bool) -> some View {
        Button(action: actions.download) {
            Label(isQueued ? "Downloading…" : "Download", systemImage: "arrow.down.circle")
        }
        .disabled(isQueued || isIgnored)

        Button(action: actions.downloadContainingFolder) {
            Label("Download entire folder", systemImage: "arrow.down.square.fill")
        }
        .disabled(isIgnored)

        Button(action: actions.browseFolder) {
            Label("Browse folder", systemImage: "folder.badge.questionmark")
        }

        Button(action: actions.browseUser) {
            Label("Browse \(result.username)", systemImage: "folder")
        }

        Button(action: actions.viewProfile) {
            Label("View profile", systemImage: "person.crop.circle")
        }

        Divider()

        if isIgnored {
            Button {
                Task { await appState.socialState.unignoreUser(result.username) }
            } label: {
                Label("Unignore user", systemImage: "eye")
            }
        } else {
            Button {
                Task { await appState.socialState.ignoreUser(result.username) }
            } label: {
                Label("Ignore user", systemImage: "eye.slash")
            }
        }

        Divider()

        Button(action: actions.copyFilename) {
            Label("Copy filename", systemImage: "doc.on.doc")
        }

        Button(action: actions.copyPath) {
            Label("Copy full path", systemImage: "link")
        }
    }
}

// MARK: - Layout anchors

/// Search-only columns. Peer anchors live in `RowLayout`, shared with the
/// transfer and history rows.
enum SearchResultRowLayout {
    /// Every search row is exactly this tall (see the `frame(height:)`
    /// note in `SearchResultRow.body`).
    static let rowHeight: CGFloat = 58

    /// Chip slot width — tuned for the longest tier label (`LOSSLESS`).
    static let qualityChipSlotWidth: CGFloat = 62

    /// Trailing action cluster: two hover-revealed secondary actions plus the
    /// prominent primary action. Shared with the grouped folder header so its
    /// download button lands under the rows' action buttons.
    static let trailingClusterWidth = RowLayout.trailingClusterWidth(secondaryActions: 2)
}

enum SearchResultStatColumn: CGFloat {
    case formatBitrate = 56   // "FLAC 4608"
    case sampleBitDepth = 46  // "176.4/24"
    case duration = 40        // "1:23:45"
    case size = 50            // "999.9 MB"

    var width: CGFloat { rawValue }
}

// MARK: - Quality tiering

enum QualityScale {
    struct Tier {
        let label: String
        let color: Color
        let helpText: String
    }

    static func tier(for r: SearchResult) -> Tier {
        if r.isLossless, let sr = r.sampleRate, sr >= 88200 {
            return Tier(
                label: "HI-RES",
                color: SeeleColors.success,
                helpText: "High-resolution lossless (≥ 88.2 kHz)"
            )
        }
        if r.isLossless {
            return Tier(
                label: "LOSSLESS",
                color: SeeleColors.success,
                helpText: "Lossless codec (FLAC, ALAC, WAV, etc.)"
            )
        }
        guard let bitrate = r.bitrate else {
            return Tier(
                label: r.fileExtension.isEmpty ? "FILE" : r.fileExtension.uppercased(),
                color: SeeleColors.textSecondary,
                helpText: "Unknown quality"
            )
        }
        if bitrate >= 320 {
            return Tier(
                label: "HQ",
                color: SeeleColors.info,
                helpText: "High-bitrate lossy (≥ 320 kbps)"
            )
        }
        if bitrate >= 192 {
            return Tier(
                label: "\(bitrate)",
                color: SeeleColors.warning,
                helpText: "Medium-bitrate lossy (\(bitrate) kbps)"
            )
        }
        return Tier(
            label: "LOW",
            color: SeeleColors.textSecondary,
            helpText: "Low-bitrate lossy (< 192 kbps)"
        )
    }

    static func color(for r: SearchResult) -> Color {
        tier(for: r).color
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Search results") {
    let samples: [SearchResult] = [
        SearchResult(
            username: "musiclover42",
            filename: "Music\\Underscores\\U\\03 - Hollywood Forever.flac",
            size: 45_000_000, bitrate: 1411, duration: 413, sampleRate: 44100, bitDepth: 16,
            freeSlots: true, uploadSpeed: 1_500_000
        ),
        SearchResult(
            username: "vinylcollector",
            filename: "Music\\MP3\\Underscores - Hollywood Forever.mp3",
            size: 8_500_000, bitrate: 320, duration: 413,
            freeSlots: false, uploadSpeed: 300_000, queueLength: 5
        ),
        SearchResult(
            username: "jazzfan",
            filename: "Downloads\\hollywoodforever.mp3",
            size: 4_200_000, bitrate: 128, duration: 413, isVBR: true,
            freeSlots: true, uploadSpeed: 80_000
        ),
        SearchResult(
            username: "hifihead",
            filename: "Audio\\High-Res\\Underscores - Hollywood Forever (2026).flac",
            size: 120_000_000, bitrate: 4608, duration: 413, sampleRate: 96000, bitDepth: 24,
            freeSlots: true, uploadSpeed: 2_400_000, isPrivate: true
        ),
        SearchResult(
            username: "random",
            filename: "stuff\\report.pdf",
            size: 250_000,
            freeSlots: true, uploadSpeed: 0
        ),
    ]

    ScrollView {
        LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
            ForEach(samples) { result in
                SearchResultRow(result: result)
            }
        }
        .background(SeeleColors.background)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD))
        .padding(SeeleSpacing.lg)
    }
    .frame(width: 900, height: 560)
    .background(SeeleColors.background)
    .previewAppState()
}

#Preview("Folder request states") {
    let idle = SearchResult(
        username: "musiclover42",
        filename: "Music\\FLAC\\Underscores\\01 - Hollywood Forever.flac",
        size: 45_000_000, bitrate: 1411, duration: 413,
        freeSlots: true, uploadSpeed: 1_500_000
    )
    let fetching = SearchResult(
        username: "vinylcollector",
        filename: "Music\\MP3\\Underscores\\02 - Hollywood Forever.mp3",
        size: 8_500_000, bitrate: 320, duration: 413,
        freeSlots: true, uploadSpeed: 300_000
    )
    let failed = SearchResult(
        username: "jazzfan",
        filename: "Audio\\Live\\Underscores\\03 - Hollywood Forever.mp3",
        size: 4_200_000, bitrate: 128, duration: 413,
        freeSlots: true, uploadSpeed: 80_000
    )

    let state = PreviewData.connectedAppState
    state.previewSeedFolderRequest(.fetching, for: fetching)
    state.previewSeedFolderRequest(
        .failed("Could not reach jazzfan after 32 seconds"),
        for: failed
    )

    return VStack(alignment: .leading, spacing: SeeleSpacing.md) {
        previewStateLabel("Idle — folder button appears on hover")
        SearchResultRow(result: idle)

        previewStateLabel("Fetching — spinner in the folder slot")
        SearchResultRow(result: fetching)

        previewStateLabel("Failed — reason on hover, clears after 30 s")
        SearchResultRow(result: failed)
    }
    .padding(SeeleSpacing.lg)
    .frame(width: 900)
    .background(SeeleColors.background)
    .previewAppState(state)
}

@ViewBuilder
private func previewStateLabel(_ text: String) -> some View {
    Text(text)
        .font(SeeleTypography.caption)
        .foregroundStyle(SeeleColors.textTertiary)
}
#endif

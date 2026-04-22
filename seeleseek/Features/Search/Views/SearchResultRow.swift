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

struct SearchResultRow: View {
    @Environment(\.appState) private var appState
    let result: SearchResult
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil

    @State private var isHovered = false

    private var downloadStatus: Transfer.TransferStatus? {
        appState.transferState.downloadStatus(for: result.filename, from: result.username)
    }

    private var isQueued: Bool {
        guard let s = downloadStatus else { return false }
        return s != .completed && s != .cancelled && s != .failed
    }

    private var isIgnored: Bool { appState.socialState.isIgnored(result.username) }

    /// Live peer status from the app-wide peer-status cache. Populated
    /// for any peer currently being watched (including transfer-list
    /// peers); search-result rows will also pick up status if the same
    /// peer later appears in a transfer.
    private var peerStatus: BuddyStatus? {
        appState.socialState.peerStatus(for: result.username)
    }

    /// Country flag for the peer. Captured at row appear rather than read
    /// in body — `UserInfoCache.countries` mutates on every GeoIP resolution
    /// and reading it live would invalidate every visible search row on
    /// every unrelated peer's country arriving. Accepts minor staleness if
    /// this user's country resolves after the row is on screen.
    @State private var countryFlag: String?

    private func refreshCountryFlag() {
        let f = appState.networkClient.userInfoCache.flag(for: result.username)
        countryFlag = f.isEmpty ? nil : f
    }

    var body: some View {
        StandardListRow(onHoverChanged: { isHovered = $0 }) {
            HStack(alignment: .top, spacing: SeeleSpacing.sm) {
                if isSelectionMode {
                    selectionCheckbox
                }

                fileGlyph

                infoColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                metadataColumn

                trailingCluster
            }
        }
        .background(selectionOverlay)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { download() }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isQueued ? [] : .isButton)
        .accessibilityActions {
            if !isQueued, !isIgnored {
                Button("Download", action: download)
            }
            Button("Browse folder", action: browseFolder)
            Button("Browse \(result.username)", action: browseUser)
        }
        .onAppear(perform: refreshCountryFlag)
        .onChange(of: result.username) { _, _ in refreshCountryFlag() }
    }

    // MARK: - Selection checkbox

    private var selectionCheckbox: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: SeeleSpacing.iconSize))
            .foregroundStyle(isSelected ? SeeleColors.accent : SeeleColors.textTertiary)
            .frame(width: SeeleSpacing.iconSizeXL, height: SeeleSpacing.iconSizeXL)
            .contentShape(Rectangle())
            .onTapGesture { onToggleSelection?() }
            .accessibilityLabel(isSelected ? "Deselect" : "Select")
            .accessibilityAddTraits(.isButton)
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
        ZStack {
            RoundedRectangle.badgeShape
                .fill(glyphTint.opacity(SeeleColors.alphaMedium))
                .frame(width: SeeleSpacing.iconSizeXL, height: SeeleSpacing.iconSizeXL)

            Image(systemName: glyphIcon)
                .font(.system(size: SeeleSpacing.iconSize, weight: .medium))
                .foregroundStyle(glyphTint)
        }
        .overlay(alignment: .bottomTrailing) {
            if result.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXXS, weight: .bold))
                    .foregroundStyle(SeeleColors.warning)
                    .padding(SeeleSpacing.xxs)
                    .background(SeeleColors.surface, in: Circle())
                    .offset(x: SeeleSpacing.xxs, y: SeeleSpacing.xxs)
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

    // MARK: - Info column (flex)

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            Text(result.displayFilename)
                .font(SeeleTypography.body)
                .foregroundStyle(isIgnored ? SeeleColors.textTertiary : SeeleColors.textPrimary)
                .strikethrough(isIgnored, color: SeeleColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)

            contextLine
        }
    }

    private var contextLine: some View {
        HStack(spacing: 0) {
            peerCell
                .frame(width: SearchResultRowLayout.peerCellWidth, alignment: .leading)

            if !result.folderPath.isEmpty {
                folderCell
            }

            Spacer(minLength: 0)
        }
    }

    private var peerCell: some View {
        HStack(spacing: 0) {
            // Username sub-cell — fixed width so peer speed lands at the
            // same X on every row.
            PeerUsernameLabel(
                iconName: "arrow.up",
                username: result.username,
                width: SearchResultRowLayout.peerUsernameWidth,
                peerStatus: peerStatus,
                countryFlag: countryFlag
            )

            Text(peerSpeedText)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(peerSpeedColor)
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var folderCell: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: "folder")
                .font(.system(size: SeeleSpacing.iconSizeXS))
                .foregroundStyle(SeeleColors.textTertiary)
                .accessibilityHidden(true)

            Text(compactFolderPath)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(result.folderPath.replacingOccurrences(of: "\\", with: "/"))
        }
    }

    /// Keeps up to the last three path components; earlier components collapse to `…`.
    private var compactFolderPath: String {
        let parts = result.folderPath.split(separator: "\\").map(String.init)
        guard !parts.isEmpty else { return "" }
        if parts.count <= 3 {
            return parts.joined(separator: "/")
        }
        return "…/" + parts.suffix(3).joined(separator: "/")
    }

    // MARK: - Metadata column (right)

    private var metadataColumn: some View {
        VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
            HStack(spacing: SeeleSpacing.sm) {
                qualityChip
                    .frame(width: SearchResultRowLayout.qualityChipSlotWidth, alignment: .trailing)
                    .accessibilityLabel(QualityScale.tier(for: result).helpText)

                techSpecColumns
            }

            secondaryMetadata
        }
    }

    private var qualityChip: some View {
        let tier = QualityScale.tier(for: result)
        return StandardMetadataBadge(tier.label, color: tier.color)
            .help(tier.helpText)
    }

    private var techSpecColumns: some View {
        HStack(spacing: SeeleSpacing.xs) {
            statCell(
                width: SearchResultStatColumn.formatBitrate.width,
                text: formatBitrateText,
                color: SeeleColors.textSecondary
            )
            statCell(
                width: SearchResultStatColumn.sampleBitDepth.width,
                text: sampleBitDepthText,
                color: SeeleColors.textTertiary
            )
            statCell(
                width: SearchResultStatColumn.duration.width,
                text: result.formattedDuration ?? "",
                color: SeeleColors.textTertiary
            )
            statCell(
                width: SearchResultStatColumn.size.width,
                text: result.formattedSize,
                color: SeeleColors.textTertiary
            )
        }
    }

    private func statCell(width: CGFloat, text: String, color: Color) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(SeeleTypography.monoSmall)
            .foregroundStyle(text.isEmpty ? SeeleColors.textTertiary : color)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    private var formatBitrateText: String {
        let ext = result.fileExtension.uppercased()
        if let bitrate = result.bitrate, bitrate > 0 {
            return "\(ext) \(bitrate)"
        }
        return ext
    }

    private var sampleBitDepthText: String {
        guard let sampleRate = result.sampleRate, sampleRate > 0 else { return "" }
        return sampleRateCompact(sampleRate)
    }

    private func sampleRateCompact(_ hz: UInt32) -> String {
        let khz = Double(hz) / 1000.0
        let base = khz == khz.rounded() ? "\(Int(khz))" : String(format: "%.1f", khz)
        if let bd = result.bitDepth, bd > 0 { return "\(base)/\(bd)" }
        return "\(base) kHz"
    }

    /// Line 2 of the metadata column. Real peer state — no estimates.
    @ViewBuilder
    private var secondaryMetadata: some View {
        if !result.freeSlots {
            HStack(spacing: SeeleSpacing.xxs) {
                Image(systemName: "hourglass")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                Text("Queue \(result.queueLength)")
                    .font(SeeleTypography.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(SeeleColors.warning)
        } else if !result.isPrivate {
            HStack(spacing: SeeleSpacing.xxs) {
                Circle()
                    .fill(SeeleColors.success)
                    .frame(
                        width: SeeleSpacing.statusDotSmall,
                        height: SeeleSpacing.statusDotSmall
                    )
                Text("Available")
                    .font(SeeleTypography.caption)
            }
            .foregroundStyle(SeeleColors.success)
        } else {
            HStack(spacing: SeeleSpacing.xxs) {
                Circle()
                    .fill(SeeleColors.warning)
                    .frame(
                        width: SeeleSpacing.statusDotSmall,
                        height: SeeleSpacing.statusDotSmall
                    )
                Text("Private")
                    .font(SeeleTypography.caption)
            }
            .foregroundStyle(SeeleColors.warning)
        }
    }

    // MARK: - Trailing cluster (hover-revealed secondary actions + primary action)

    private static let secondaryActionCount: CGFloat = 2
    private var secondaryActionsWidth: CGFloat {
        SeeleSpacing.buttonHeight * Self.secondaryActionCount
            + SeeleSpacing.xxs * (Self.secondaryActionCount - 1)
    }
    private var trailingClusterWidth: CGFloat {
        secondaryActionsWidth + SeeleSpacing.xxs + SeeleSpacing.iconSizeXL
    }

    private var trailingCluster: some View {
        HStack(spacing: SeeleSpacing.xxs) {
            secondaryActions
            primaryAction
        }
        .frame(width: trailingClusterWidth, alignment: .trailing)
    }

    private var secondaryActions: some View {
        // Hit-testing stays on even at opacity 0 so Tab focus (and, via
        // `accessibilityAction` below, VoiceOver rotor) can reach these
        // actions. The invisible focus ring is an accepted tradeoff.
        HStack(spacing: SeeleSpacing.xxs) {
            RowIconButton(
                systemName: "folder.badge.questionmark",
                help: "Browse this folder",
                action: browseFolder
            )
            RowIconButton(
                systemName: "person.crop.circle",
                help: "Browse \(result.username)'s files",
                action: browseUser
            )
        }
        .opacity(isHovered ? 1 : 0)
        .frame(width: secondaryActionsWidth, alignment: .trailing)
    }

    private var primaryAction: some View {
        Button(action: download) {
            Image(systemName: actionIcon)
                .font(.system(size: SeeleSpacing.iconSizeMedium, weight: .semibold))
                .foregroundStyle(actionColor)
                .frame(width: SeeleSpacing.iconSizeXL, height: SeeleSpacing.iconSizeXL)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isQueued || isIgnored)
        .help(actionHelp)
        .accessibilityLabel(actionHelp)
    }

    private var actionIcon: String {
        switch downloadStatus {
        case .completed: "checkmark.circle.fill"
        case .transferring, .queued, .waiting, .connecting: "arrow.down.circle.fill"
        case .failed, .cancelled: "arrow.clockwise.circle"
        case .none: "arrow.down.circle"
        }
    }

    private var actionColor: Color {
        if isIgnored { return SeeleColors.textTertiary }
        return switch downloadStatus {
        case .completed: SeeleColors.success
        case .transferring, .queued, .waiting, .connecting: SeeleColors.accent
        case .failed, .cancelled: SeeleColors.warning
        case .none: isHovered ? SeeleColors.accent : SeeleColors.textSecondary
        }
    }

    private var actionHelp: String {
        if isIgnored { return "User is ignored" }
        return switch downloadStatus {
        case .completed: "Already downloaded"
        case .transferring: "Downloading…"
        case .queued, .waiting, .connecting: "In queue"
        case .failed, .cancelled: "Retry download"
        case .none: "Download"
        }
    }

    // MARK: - Peer speed formatting

    /// Peer's reported upload speed. In SoulSeek this is the rate at which
    /// *they* serve files, which is usually more predictive of download
    /// time than the file size alone.
    private var peerSpeedText: String {
        let bytesPerSecond = UInt64(result.uploadSpeed)
        guard bytesPerSecond > 0 else { return "unknown" }
        return bytesPerSecond.formattedBytes + "/s"
    }

    /// Tinted by peer quality tier.
    ///   ≥ 1 MB/s: success (fast peer)
    ///   ≥ 200 KB/s: info (decent peer)
    ///   < 200 KB/s: warning (slow peer)
    ///   unknown: tertiary (no signal)
    private var peerSpeedColor: Color {
        let bps = result.uploadSpeed
        if bps == 0 { return SeeleColors.textTertiary }
        if bps >= 1_000_000 { return SeeleColors.success }
        if bps >= 200_000 { return SeeleColors.info }
        return SeeleColors.warning
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
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

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button(action: download) {
            Label(isQueued ? "Downloading…" : "Download", systemImage: "arrow.down.circle")
        }
        .disabled(isQueued || isIgnored)

        Button(action: downloadContainingFolder) {
            Label("Download entire folder", systemImage: "arrow.down.square.fill")
        }
        .disabled(isIgnored)

        Button(action: browseFolder) {
            Label("Browse folder", systemImage: "folder.badge.questionmark")
        }

        Button(action: browseUser) {
            Label("Browse \(result.username)", systemImage: "folder")
        }

        Button {
            Task { await appState.socialState.loadProfile(for: result.username) }
        } label: {
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

        Button(action: copyFilename) {
            Label("Copy filename", systemImage: "doc.on.doc")
        }

        Button(action: copyPath) {
            Label("Copy full path", systemImage: "link")
        }
    }

    // MARK: - Actions

    private func download() {
        guard !isQueued, !isIgnored else { return }
        appState.downloadManager.queueDownload(from: result)
    }

    private func browseUser() {
        appState.browseState.browseUser(result.username)
        appState.sidebarSelection = .browse
    }

    private func browseFolder() {
        appState.browseState.browseUser(result.username, targetPath: result.filename)
        appState.sidebarSelection = .browse
    }

    private func downloadContainingFolder() {
        Task { await appState.downloadContainingFolder(of: result) }
    }

    private func copyFilename() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.displayFilename, forType: .string)
        #endif
    }

    private func copyPath() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.filename, forType: .string)
        #endif
    }
}

// MARK: - Layout anchors
//
// Fixed widths so the same field lands at the same X coordinate on every
// row. Kept as tight as possible — extra width shows up as dead space.

enum SearchResultRowLayout {
    /// Fixed sub-cell width for the username so the peer *speed* lands at
    /// the same X on every row. Anything longer truncates from the tail.
    static let peerUsernameWidth: CGFloat = 96

    /// Outer peer-cell width (username sub-cell + speed + slack). Fixed so
    /// the folder icon lands at the same X on every row.
    static let peerCellWidth: CGFloat = 168

    /// Chip slot width — tuned for the longest tier label (`LOSSLESS`).
    static let qualityChipSlotWidth: CGFloat = 62
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
#endif

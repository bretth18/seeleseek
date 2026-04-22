import SwiftUI
import SeeleseekCore

// MARK: - Layout anchors

/// Fixed widths so the same field lands at the same X coordinate on every
/// transfer row. Peer sub-cell sizing matches SearchResultRow so rows
/// across the app belong to the same visual family.
enum TransferRowLayout {
    static let peerUsernameWidth: CGFloat = 96     // tail-truncates longer names
    static let peerCellWidth: CGFloat = 168        // username sub-cell + slack
    static let sparklineWidth: CGFloat = 64        // snug next to the speed value
    static let sparklineHeight: CGFloat = 16       // matches a caption's line box
    static let speedColumnWidth: CGFloat = 82      // "245.2 KB/s"
    static let secondaryColumnWidth: CGFloat = 150 // "18.6 MB / 120.4 MB"
}

// MARK: - Row

/// Compact transfer row with two progress signals:
///   - A 2pt progress hairline along the bottom edge (overall completion).
///   - An inline speed sparkline beside the speed value (speed stability
///     over the last ~30 samples).
///
/// Both are optional: the hairline only draws for active/completed
/// transfers, and the sparkline only draws while `.transferring`. Slot
/// widths stay constant so column anchors never shift.
///
/// Layout:
///   [⇣glyph]  filename                      ▂▄▆▇▆ 245.2 KB/s   [× cancel]
///             ↑ user · folder / path              41% · 18.6 / 45 MB
///   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   progress hairline
struct TransferRow: View {
    @Environment(\.appState) private var appState
    let transfer: Transfer
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    var onMoveToTop: (() -> Void)? = nil
    var onMoveToBottom: (() -> Void)? = nil

    @State private var isHovered = false

    /// Peer status captured at row appear rather than read live from
    /// `SocialState.peerStatuses`. Every status update mutates the whole
    /// observable dict, which invalidated every visible row in the
    /// transfer list — the same anti-pattern the country flag already
    /// avoided here. Accepts minor staleness; the next appearance (scroll
    /// off/on or username change) resamples.
    @State private var peerStatus: BuddyStatus?

    private func refreshPeerStatus() {
        peerStatus = appState.socialState.peerStatus(for: transfer.username)
    }

    /// True only if the app-wide audio preview is currently playing
    /// *this row's* file. Preview state lives on `AppState` so starting
    /// playback elsewhere flips this row's button back to "play".
    private var isPlayingPreview: Bool {
        guard let path = transfer.localPath else { return false }
        return appState.audioPreview.isPlaying(url: path)
    }

    /// Country flag emoji for the peer. Captured at row appear rather than
    /// live-read; see SearchResultRow / HistoryRow for the same pattern.
    @State private var countryFlag: String?

    private func refreshCountryFlag() {
        let f = appState.networkClient.userInfoCache.flag(for: transfer.username)
        countryFlag = f.isEmpty ? nil : f
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardListRow(onHoverChanged: { isHovered = $0 }) {
                HStack(alignment: .top, spacing: SeeleSpacing.sm) {
                    TransferDirectionGlyph(transfer: transfer)

                    TransferInfoColumn(
                        transfer: transfer,
                        peerStatus: peerStatus,
                        countryFlag: countryFlag
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TransferMetadataColumn(
                        transfer: transfer
                    )

                    TransferActionCluster(
                        transfer: transfer,
                        isHovered: isHovered,
                        isPlaying: isPlayingPreview,
                        onCancel: onCancel,
                        onRetry: onRetry,
                        onRemove: onRemove,
                        onReveal: revealInFinder,
                        onTogglePreview: toggleAudioPreview,
                        onEditMetadata: openMetadataEditor
                    )
                }
            }

            TransferProgressHairline(transfer: transfer)
        }
        .contentShape(Rectangle())
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .modifier(TransferRowAccessibilityActions(
            transfer: transfer,
            isPlaying: isPlayingPreview,
            onCancel: onCancel,
            onRetry: onRetry,
            onRemove: onRemove,
            onReveal: revealInFinder,
            onTogglePreview: toggleAudioPreview,
            onEditMetadata: openMetadataEditor
        ))
        .onAppear {
            refreshCountryFlag()
            refreshPeerStatus()
        }
        .onChange(of: transfer.username) { _, _ in
            refreshCountryFlag()
            refreshPeerStatus()
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        if let onMoveToTop,
           let onMoveToBottom,
           transfer.status == .queued || transfer.status == .waiting {
            Button(action: onMoveToTop) {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
            Button(action: onMoveToBottom) {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
            Divider()
        }

        if transfer.status == .completed, transfer.isAudioFile, transfer.localPath != nil {
            Button(action: toggleAudioPreview) {
                Label(
                    isPlayingPreview ? "Stop Preview" : "Play Preview",
                    systemImage: isPlayingPreview ? "stop.fill" : "play.fill"
                )
            }
            Button(action: openMetadataEditor) {
                Label("Edit Metadata", systemImage: "tag")
            }
        }

        if transfer.status == .completed, transfer.localPath != nil {
            Button(action: revealInFinder) {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Divider()
        }

        if !transfer.isActive, transfer.status != .completed {
            Button(role: .destructive, action: onRemove) {
                Label("Remove from List", systemImage: "trash")
            }
            Divider()
        }

        UserContextMenuItems(username: transfer.username)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts: [String] = [transfer.displayFilename]
        parts.append(transfer.direction == .download ? "from \(transfer.username)" : "to \(transfer.username)")
        parts.append(transfer.status.displayText)
        if transfer.status == .transferring {
            parts.append("\(Int(transfer.progress * 100)) percent")
            parts.append(transfer.formattedSpeed)
        } else if let error = transfer.error {
            parts.append(error)
        } else if let pos = transfer.queuePosition {
            parts.append("queue position \(pos)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Actions

    private func revealInFinder() {
        guard let path = transfer.localPath else { return }
        FileReveal.inFinder(path)
    }

    private func toggleAudioPreview() {
        guard let path = transfer.localPath else { return }
        appState.audioPreview.toggle(url: path)
    }

    private func openMetadataEditor() {
        guard let path = transfer.localPath else { return }
        appState.metadataState.showEditor(for: path)
    }
}

// MARK: - Accessibility actions
//
// Secondary actions (play, tag, reveal, remove) are hover-revealed for
// sighted users. These entries surface them in the VoiceOver rotor so
// assistive-tech users don't have to open the context menu.

private struct TransferRowAccessibilityActions: ViewModifier {
    let transfer: Transfer
    let isPlaying: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void
    let onTogglePreview: () -> Void
    let onEditMetadata: () -> Void

    private var isCompletedAudio: Bool {
        transfer.status == .completed && transfer.isAudioFile && transfer.localPath != nil
    }
    private var hasCompletedFile: Bool {
        transfer.status == .completed && transfer.localPath != nil
    }
    private var canRemove: Bool {
        !transfer.isActive && transfer.status != .completed
    }

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if transfer.canCancel {
                Button("Cancel", action: onCancel)
            }
            if transfer.canRetry {
                Button("Retry", action: onRetry)
            }
            if isCompletedAudio {
                Button(isPlaying ? "Stop preview" : "Play preview", action: onTogglePreview)
                Button("Edit metadata", action: onEditMetadata)
            }
            if hasCompletedFile {
                Button("Reveal in Finder", action: onReveal)
            }
            if canRemove {
                Button("Remove from list", action: onRemove)
            }
        }
    }
}

// MARK: - Direction glyph

private struct TransferDirectionGlyph: View {
    let transfer: Transfer

    var body: some View {
        RowDirectionGlyph(
            direction: transfer.direction == .download ? .download : .upload,
            tint: transfer.statusColor,
            isConnecting: transfer.status == .connecting
        )
    }
}

// MARK: - Info column (flex, left)

private struct TransferInfoColumn: View {
    let transfer: Transfer
    let peerStatus: BuddyStatus?
    let countryFlag: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            Text(transfer.displayFilename)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)

            contextLine
        }
    }

    /// Whether we know the peer is offline. `.away` still serves files
    /// (the user's just AFK) so it's not a failure reason. We only
    /// surface this for stalled rows — an actively-transferring row's
    /// liveness is self-evident.
    private var peerIsOffline: Bool {
        guard peerStatus == .offline else { return false }
        return transfer.status == .failed
            || transfer.status == .cancelled
            || transfer.status == .waiting
            || transfer.status == .queued
    }

    /// Detail shown to the right of the peer cluster. Only one of the
    /// following renders, in priority order:
    ///   1. Explicit "Peer offline/away" when the server told us so.
    ///   2. `transfer.error` (e.g. "Upload failed on peer side").
    ///   3. Folder path (for context on active/queued transfers).
    ///   4. Retry count badge.
    /// Wasteful 168pt outer peer-cell only kicks in for case 3 — where
    /// cross-row folder-path alignment matters. Cases 1/2/4 use intrinsic
    /// peer-cluster width so the detail butts up right after the username.
    @ViewBuilder
    private var contextLine: some View {
        if peerIsOffline {
            HStack(spacing: SeeleSpacing.md) {
                peerCluster
                offlineLabel
                Spacer(minLength: 0)
            }
        } else if let error = transfer.error, !error.isEmpty {
            HStack(spacing: SeeleSpacing.md) {
                peerCluster
                errorLabel(error)
                Spacer(minLength: 0)
            }
        } else if let folder = transfer.folderPath, !folder.isEmpty {
            HStack(spacing: 0) {
                peerCluster
                    .frame(width: TransferRowLayout.peerCellWidth, alignment: .leading)
                folderCell(folder)
                Spacer(minLength: 0)
            }
        } else if transfer.retryCount > 0 {
            HStack(spacing: SeeleSpacing.md) {
                peerCluster
                retryLabel
                Spacer(minLength: 0)
            }
        } else {
            peerCluster
        }
    }

    private var peerCluster: some View {
        HStack(spacing: SeeleSpacing.xs) {
            PeerUsernameLabel(
                iconName: transfer.direction == .download ? "arrow.down" : "arrow.up",
                username: transfer.username,
                width: TransferRowLayout.peerUsernameWidth,
                peerStatus: peerStatus,
                countryFlag: countryFlag
            )

            if transfer.retryCount > 0, transfer.error != nil {
                Text("retry \(transfer.retryCount)")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.warning)
                    .monospacedDigit()
            }
        }
    }

    private var offlineLabel: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: "wifi.slash")
                .font(.system(size: SeeleSpacing.iconSizeXS))
                .foregroundStyle(SeeleColors.error)
                .accessibilityHidden(true)

            Text("Peer offline")
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.error)
                .lineLimit(1)
        }
    }

    private func folderCell(_ folder: String) -> some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: "folder")
                .font(.system(size: SeeleSpacing.iconSizeXS))
                .foregroundStyle(SeeleColors.textTertiary)
                .accessibilityHidden(true)

            Text(folder)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder)
        }
    }

    private func errorLabel(_ error: String) -> some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: SeeleSpacing.iconSizeXS))
                .foregroundStyle(SeeleColors.error)
                .accessibilityHidden(true)

            Text(error)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.error)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(error)
        }
    }

    private var retryLabel: some View {
        HStack(spacing: SeeleSpacing.xs) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: SeeleSpacing.iconSizeXS))
                .foregroundStyle(SeeleColors.warning)
                .accessibilityHidden(true)

            Text("retry \(transfer.retryCount)")
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.warning)
                .monospacedDigit()
        }
    }
}

// MARK: - Metadata column (right, two tiers)

private struct TransferMetadataColumn: View {
    @Environment(\.appState) private var appState
    let transfer: Transfer

    private var line1Width: CGFloat {
        TransferRowLayout.sparklineWidth
            + SeeleSpacing.xs
            + TransferRowLayout.speedColumnWidth
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
            primaryLine
                .frame(width: line1Width, alignment: .trailing)

            secondaryStat
                .frame(width: TransferRowLayout.secondaryColumnWidth, alignment: .trailing)
        }
    }

    private var primaryLine: some View {
        HStack(spacing: SeeleSpacing.xs) {
            sparklineSlot
            primaryStat
                .frame(width: TransferRowLayout.speedColumnWidth, alignment: .trailing)
        }
    }

    private var sparklineSlot: some View {
        Group {
            if transfer.status == .transferring {
                // Poll the non-observable speed-history accessor every
                // second. `speedHistory(for:)` doesn't register an
                // Observation dependency, so only this sparkline view
                // refreshes on each tick — the enclosing row and list
                // stay idle even while sampling is active.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    TransferSparkline(
                        values: appState.transferState.speedHistory(for: transfer.id),
                        tint: SeeleColors.accent
                    )
                }
                .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
        .frame(
            width: TransferRowLayout.sparklineWidth,
            height: TransferRowLayout.sparklineHeight
        )
    }

    @ViewBuilder
    private var primaryStat: some View {
        switch transfer.status {
        case .transferring:
            Text(transfer.formattedSpeed)
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.accent)
                .monospacedDigit()
                .lineLimit(1)
        case .waiting:
            HStack(spacing: SeeleSpacing.xxs) {
                Image(systemName: "hourglass")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                Text(queueLabel)
                    .font(SeeleTypography.monoSmall)
                    .monospacedDigit()
            }
            .foregroundStyle(SeeleColors.warning)
        case .connecting:
            Text("Connecting")
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.info)
        case .queued:
            Text("Queued")
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.warning)
        case .completed:
            HStack(spacing: SeeleSpacing.xxs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                Text("Complete")
                    .font(SeeleTypography.monoSmall)
            }
            .foregroundStyle(SeeleColors.success)
        case .failed:
            Text("Failed")
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.error)
        case .cancelled:
            Text("Cancelled")
                .font(SeeleTypography.monoSmall)
                .foregroundStyle(SeeleColors.textTertiary)
        }
    }

    private var secondaryStat: some View {
        Text(secondaryText)
            .font(SeeleTypography.monoSmall)
            .foregroundStyle(SeeleColors.textTertiary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var secondaryText: String {
        switch transfer.status {
        case .transferring, .connecting:
            let pct = Int(transfer.progress * 100)
            return "\(pct)% · \(transfer.bytesTransferred.formattedBytes)/\(transfer.size.formattedBytes)"
        default:
            return transfer.size.formattedBytes
        }
    }

    private var queueLabel: String {
        if let pos = transfer.queuePosition {
            return "#\(pos)"
        }
        return "Waiting"
    }
}

// MARK: - Action cluster (right edge, fixed width)

private struct TransferActionCluster: View {
    let transfer: Transfer
    let isHovered: Bool
    let isPlaying: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void
    let onTogglePreview: () -> Void
    let onEditMetadata: () -> Void

    /// Reserve width for up to three hover-revealed secondary icons:
    /// play / tag / reveal on completed audio files. Unused slots stay
    /// blank so the row doesn't reflow.
    private static let secondaryActionCount: CGFloat = 3
    private var secondaryActionsWidth: CGFloat {
        SeeleSpacing.buttonHeight * Self.secondaryActionCount
            + SeeleSpacing.xxs * (Self.secondaryActionCount - 1)
    }
    private var clusterWidth: CGFloat {
        secondaryActionsWidth + SeeleSpacing.xxs + SeeleSpacing.iconSizeXL
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.xxs) {
            secondaryActions
            primaryAction
        }
        .frame(width: clusterWidth, alignment: .trailing)
    }

    private var secondaryActions: some View {
        // Hit-testing stays on even at opacity 0 so Tab focus (and, via
        // `accessibilityAction` on the row, VoiceOver rotor) can reach
        // these actions. The invisible focus ring is an accepted tradeoff.
        HStack(spacing: SeeleSpacing.xxs) {
            if transfer.status == .completed,
               transfer.isAudioFile,
               transfer.localPath != nil {
                RowIconButton(
                    systemName: isPlaying ? "pause.fill" : "play.fill",
                    help: isPlaying ? "Pause preview" : "Play preview",
                    action: onTogglePreview
                )

                RowIconButton(
                    systemName: "tag",
                    help: "Edit metadata",
                    action: onEditMetadata
                )
            }

            if transfer.status == .completed, transfer.localPath != nil {
                RowIconButton(
                    systemName: "folder",
                    help: "Reveal in Finder",
                    action: onReveal
                )
            } else if !transfer.isActive {
                RowIconButton(
                    systemName: "trash",
                    help: "Remove from list",
                    tint: SeeleColors.textTertiary,
                    action: onRemove
                )
            }
        }
        .opacity(isHovered ? 1 : 0)
        .frame(width: secondaryActionsWidth, alignment: .trailing)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if transfer.canCancel {
            primaryButton(
                icon: "xmark.circle.fill",
                help: "Cancel transfer",
                tint: SeeleColors.textSecondary,
                action: onCancel
            )
        } else if transfer.canRetry {
            primaryButton(
                icon: "arrow.clockwise.circle",
                help: "Retry transfer",
                tint: SeeleColors.warning,
                action: onRetry
            )
        } else if transfer.status == .completed {
            primaryButton(
                icon: "checkmark.circle.fill",
                help: "Downloaded",
                tint: SeeleColors.success,
                action: {}
            )
            .disabled(true)
        } else {
            Color.clear
                .frame(
                    width: SeeleSpacing.iconSizeXL,
                    height: SeeleSpacing.iconSizeXL
                )
        }
    }

    private func primaryButton(
        icon: String,
        help: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: SeeleSpacing.iconSizeMedium, weight: .semibold))
                .foregroundStyle(tint)
                .frame(
                    width: SeeleSpacing.iconSizeXL,
                    height: SeeleSpacing.iconSizeXL
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Progress hairline

private struct TransferProgressHairline: View {
    let transfer: Transfer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(SeeleColors.textTertiary.opacity(SeeleColors.alphaMedium))
                    .frame(height: SeeleSpacing.strokeMedium)

                Rectangle()
                    .fill(transfer.statusColor)
                    .frame(
                        width: geo.size.width * transfer.progress,
                        height: SeeleSpacing.strokeMedium
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: SeeleSpacing.animationStandard),
                        value: transfer.progress
                    )
            }
        }
        .frame(height: SeeleSpacing.strokeMedium)
        .opacity(transfer.isActive || transfer.status == .completed ? 1 : 0)
    }
}

// MARK: - Sparkline primitive

/// Minimal line + filled-area chart. Driven by an `[Int64]` of speed
/// samples ordered oldest → newest. Renders nothing until at least two
/// samples arrive, so an empty array is safe.
struct TransferSparkline: View {
    let values: [Int64]
    var tint: Color = .accentColor

    /// Max samples rendered. Matches `TransferState.speedHistoryLimit` —
    /// extra samples are silently dropped from the left.
    static let sampleLimit = 30

    var body: some View {
        GeometryReader { geo in
            let samples = values.suffix(Self.sampleLimit)
            let maxV = max(samples.max() ?? 0, 1)
            let step = samples.count > 1 ? geo.size.width / CGFloat(samples.count - 1) : 0

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(tint.opacity(SeeleColors.alphaLight))
                    .frame(height: SeeleSpacing.strokeThin)

                if samples.count >= 2 {
                    Path { path in
                        for (idx, v) in samples.enumerated() {
                            let x = step * CGFloat(idx)
                            let h = geo.size.height * CGFloat(v) / CGFloat(maxV)
                            let y = geo.size.height - h
                            if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(
                        tint,
                        style: StrokeStyle(
                            lineWidth: SeeleSpacing.strokeMedium,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (idx, v) in samples.enumerated() {
                            let x = step * CGFloat(idx)
                            let h = geo.size.height * CGFloat(v) / CGFloat(maxV)
                            let y = geo.size.height - h
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(tint.opacity(SeeleColors.alphaMedium))
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Transfer rows") {
    let downloading = Transfer(
        username: "musiclover42",
        filename: "@@music\\Pink Floyd\\The Dark Side of the Moon\\03 - Time.flac",
        size: 45_000_000,
        direction: .download,
        status: .transferring,
        bytesTransferred: 18_600_000,
        startTime: Date().addingTimeInterval(-120),
        speed: 180_000
    )
    let uploading = Transfer(
        username: "stranger",
        filename: "@@music\\Miles Davis\\Kind of Blue\\01 - So What.flac",
        size: 32_000_000,
        direction: .upload,
        status: .transferring,
        bytesTransferred: 9_800_000,
        startTime: Date().addingTimeInterval(-40),
        speed: 245_000
    )
    let queued = Transfer(
        username: "vinylcollector",
        filename: "@@rock\\Led Zeppelin\\IV\\01 - Black Dog.flac",
        size: 40_000_000,
        direction: .download,
        status: .waiting,
        queuePosition: 3
    )
    let failed = Transfer(
        username: "offlineuser",
        filename: "@@rock\\Nirvana\\Nevermind\\01 - Smells Like Teen Spirit.mp3",
        size: 9_000_000,
        direction: .download,
        status: .failed,
        error: "Peer offline",
        retryCount: 2
    )
    let done = Transfer(
        username: "hifihead",
        filename: "@@hi-res\\Radiohead\\OK Computer\\06 - Karma Police.flac",
        size: 68_000_000,
        direction: .download,
        status: .completed,
        bytesTransferred: 68_000_000,
        startTime: Date().addingTimeInterval(-500),
        speed: 220_000,
        localPath: URL(fileURLWithPath: "/tmp/placeholder.flac")
    )

    // Synthetic sparkline data for preview only.
    let sparkDownloading = (0..<28).map { i -> Int64 in
        let base = 180_000.0
        let wave = sin(Double(i) * 0.35) * 40_000
        let noise = Double.random(in: -15_000...15_000)
        return max(20_000, Int64(base + wave + noise))
    }
    let sparkUploading = (0..<28).map { i -> Int64 in
        let base = 245_000.0
        let ramp = Double(i) * 2_500
        let noise = Double.random(in: -20_000...20_000)
        return max(60_000, Int64(base + ramp + noise))
    }

    ScrollView {
        LazyVStack(spacing: SeeleSpacing.dividerSpacing) {
            TransferRow(
                transfer: downloading,
                onCancel: {}, onRetry: {}, onRemove: {}
            )
            TransferRow(
                transfer: uploading,
                onCancel: {}, onRetry: {}, onRemove: {}
            )
            TransferRow(transfer: queued, onCancel: {}, onRetry: {}, onRemove: {})
            TransferRow(transfer: failed, onCancel: {}, onRetry: {}, onRemove: {})
            TransferRow(transfer: done, onCancel: {}, onRetry: {}, onRemove: {})
        }
        .background(SeeleColors.background)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD))
        .padding(SeeleSpacing.lg)
    }
    .frame(width: 900, height: 520)
    .background(SeeleColors.background)
    .previewAppState()
}
#endif

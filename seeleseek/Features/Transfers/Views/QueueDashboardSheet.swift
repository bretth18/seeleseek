import SwiftUI
import SeeleseekCore

// MARK: - Status bucketing

/// Collapses the seven `Transfer.TransferStatus` cases into the five
/// buckets the dashboard cares about. `.failed` splits into "retrying"
/// (auto-retry pending) vs "failed" (terminal) so the user can see at
/// a glance which failures will resolve themselves and which need
/// attention. `.connecting` rolls into `.queued` since they're both
/// pre-active states from a queue-watcher's perspective.
enum QueueBucket: String, CaseIterable, Identifiable {
    case transferring
    case waiting
    case queued
    case retrying
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transferring: "Active"
        case .waiting: "Waiting"
        case .queued: "Queued"
        case .retrying: "Retrying"
        case .failed: "Failed"
        }
    }

    var color: Color {
        switch self {
        case .transferring: SeeleColors.success
        case .waiting: SeeleColors.info
        case .queued: SeeleColors.warning
        case .retrying: Color(hex: 0xFB923C)  // orange between warning and error
        case .failed: SeeleColors.error
        }
    }

    static func from(_ transfer: Transfer) -> QueueBucket? {
        switch transfer.status {
        case .transferring: return .transferring
        case .connecting: return .queued
        case .waiting: return .waiting
        case .queued: return .queued
        case .failed: return transfer.isPendingRetry ? .retrying : .failed
        case .completed, .cancelled: return nil  // not part of the live queue
        }
    }
}

// MARK: - Sheet

/// Visual dashboard of the active transfer queue. Replaces "scroll the
/// list to count what's where" with a dense at-a-glance picture: status
/// totals, a pipeline strip, and per-peer lanes that show *which peer*
/// you're waiting on the most. Refreshes live via `@Environment(\.appState)`
/// observation; bytes-pending ticker uses `TimelineView` for sub-second
/// liveness.
struct QueueDashboardSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    private var transferState: TransferState { appState.transferState }

    // Queue lives in both download + upload arrays. We're showing one
    // unified picture; direction is denoted by the row's icon, not by
    // splitting the dashboard into two halves.
    private var liveTransfers: [Transfer] {
        (transferState.downloads + transferState.uploads).filter { QueueBucket.from($0) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().background(SeeleColors.divider)

            if liveTransfers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SeeleSpacing.xl) {
                        statsRow
                        pipelineStrip
                        perPeerSection
                    }
                    .padding(SeeleSpacing.lg)
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 520, idealHeight: 680)
        .background(SeeleColors.background)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(spacing: SeeleSpacing.md) {
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text("Queue dashboard")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)
                Text("Live view of every transfer that hasn't completed or been cancelled")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SeeleColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(SeeleColors.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.md)
        .background(SeeleColors.surface)
    }

    // MARK: - Stats row

    private var statsRow: some View {
        let counts = Dictionary(grouping: liveTransfers, by: { QueueBucket.from($0)! }).mapValues(\.count)
        let totalBytes = liveTransfers.reduce(UInt64(0)) { $0 + $1.size }
        let activeSpeed = transferState.totalDownloadSpeed + transferState.totalUploadSpeed

        return HStack(alignment: .top, spacing: SeeleSpacing.lg) {
            ForEach(QueueBucket.allCases) { bucket in
                statCell(label: bucket.label, count: counts[bucket] ?? 0, color: bucket.color)
            }
            Divider().frame(height: 36).background(SeeleColors.divider)
            statCell(label: "Pending bytes", count: nil, secondary: totalBytes.formattedBytes, color: SeeleColors.textPrimary)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                statCell(
                    label: "Throughput",
                    count: nil,
                    secondary: activeSpeed.formattedSpeed,
                    color: SeeleColors.accent
                )
            }
        }
    }

    private func statCell(label: String, count: Int?, secondary: String? = nil, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(SeeleTypography.caption2)
                .tracking(0.5)
                .foregroundStyle(SeeleColors.textTertiary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
            } else if let secondary {
                Text(secondary)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Pipeline strip

    /// Horizontal stacked bar partitioned by status. Width proportions
    /// are by total *bytes* in each bucket, not file count, because a
    /// 10 GB transfer in `.transferring` is more meaningful than 50
    /// tiny `.queued` rows. Counts overlay each segment.
    private var pipelineStrip: some View {
        let grouped = Dictionary(grouping: liveTransfers, by: { QueueBucket.from($0)! })
        let totals: [(bucket: QueueBucket, bytes: UInt64, count: Int)] = QueueBucket.allCases.compactMap { bucket in
            guard let rows = grouped[bucket], !rows.isEmpty else { return nil }
            let bytes = rows.reduce(UInt64(0)) { $0 + $1.size }
            return (bucket, bytes, rows.count)
        }
        let totalBytes = max(UInt64(1), totals.reduce(UInt64(0)) { $0 + $1.bytes })

        return VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
            Text("Pipeline")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)

            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(totals, id: \.bucket) { entry in
                        let frac = Double(entry.bytes) / Double(totalBytes)
                        let width = max(36, geo.size.width * frac)
                        ZStack {
                            entry.bucket.color
                            Text("\(entry.count)")
                                .font(SeeleTypography.monoSmall)
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        .frame(width: width)
                        .help("\(entry.bucket.label): \(entry.count) · \(entry.bytes.formattedBytes)")
                    }
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: SeeleSpacing.md) {
                ForEach(totals, id: \.bucket) { entry in
                    legendDot(color: entry.bucket.color, label: entry.bucket.label)
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }

    // MARK: - Per-peer lanes

    /// Each row = one peer. The bar shows that peer's individual
    /// transfers as proportional segments (width = file size) colored
    /// by status. Hovering a segment reveals filename + status. Sorting
    /// is by total queued-and-active bytes descending — bigger bottlenecks
    /// rise to the top.
    private var perPeerSection: some View {
        let byPeer = Dictionary(grouping: liveTransfers, by: \.username)
        let lanes = byPeer.map { (peer: $0.key, transfers: $0.value, totalBytes: $0.value.reduce(UInt64(0)) { $0 + $1.size }) }
            .sorted { $0.totalBytes > $1.totalBytes }

        return VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            HStack {
                Text("By peer")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                Spacer()
                Text("\(lanes.count) peer\(lanes.count == 1 ? "" : "s")")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            VStack(spacing: SeeleSpacing.sm) {
                ForEach(lanes, id: \.peer) { lane in
                    PeerLane(peer: lane.peer, transfers: lane.transfers, totalBytes: lane.totalBytes)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: SeeleSpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(SeeleColors.textTertiary)
            Text("Queue is empty")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textSecondary)
            Text("Nothing active, queued, waiting, retrying, or failed.")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SeeleSpacing.xxl)
    }
}

// MARK: - Peer lane

private struct PeerLane: View {
    let peer: String
    let transfers: [Transfer]
    let totalBytes: UInt64

    /// Order within a lane: active first, then waiting, then queued,
    /// then retrying, then failed — matches the user's intuition that
    /// "what's happening now" should be on the left.
    private var orderedTransfers: [Transfer] {
        transfers.sorted { lhs, rhs in
            let li = laneOrder(QueueBucket.from(lhs) ?? .queued)
            let ri = laneOrder(QueueBucket.from(rhs) ?? .queued)
            if li != ri { return li < ri }
            return lhs.size > rhs.size  // bigger files first within a bucket
        }
    }

    private func laneOrder(_ b: QueueBucket) -> Int {
        switch b {
        case .transferring: 0
        case .waiting: 1
        case .queued: 2
        case .retrying: 3
        case .failed: 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(SeeleColors.textTertiary)
                Text(peer)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                Spacer()
                Text("\(transfers.count) file\(transfers.count == 1 ? "" : "s") · \(totalBytes.formattedBytes)")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(orderedTransfers) { transfer in
                        let bucket = QueueBucket.from(transfer) ?? .queued
                        let frac = totalBytes > 0 ? Double(transfer.size) / Double(totalBytes) : 0
                        let width = max(3, geo.size.width * frac)
                        Rectangle()
                            .fill(bucket.color)
                            .frame(width: width)
                            .overlay(progressOverlay(for: transfer, width: width), alignment: .leading)
                            .help("\(transfer.displayFilename) · \(bucket.label) · \(transfer.size.formattedBytes)")
                    }
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(SeeleSpacing.sm)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: SeeleSpacing.cornerRadiusSmall)
                .stroke(SeeleColors.divider, lineWidth: 1)
        )
    }

    /// For `.transferring` segments, paint a brighter overlay sized to
    /// `progress` so a half-done file looks half-done at a glance —
    /// turns a static colored bar into a live progress visualization.
    @ViewBuilder
    private func progressOverlay(for transfer: Transfer, width: CGFloat) -> some View {
        if transfer.status == .transferring, transfer.progress > 0 {
            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(width: width * CGFloat(transfer.progress))
        }
    }
}

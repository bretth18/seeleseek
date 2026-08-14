import SwiftUI
import SeeleseekCore

struct SharesVisualizationPanel: View {
    let shares: UserShares

    /// Only what the sections render — never hold the flat file arrays in
    /// view state (~2 GB on mega-shares).
    struct Summary: Sendable {
        let typeEntries: [FileTypeDistribution.Entry]
        let typeTotalSize: UInt64
        let bitrateBuckets: [BitrateDistribution.Bucket]
        let hasAudio: Bool
        let topFiles: [(String, UInt64)]
        let treemapFiles: [SharedFile]
        let hasFiles: Bool
    }

    /// Keyed by `shares.id` so switching tabs and back does not re-run the
    /// full-tree walk. A refresh mints a new UserShares id, so stale entries
    /// are never served; the cap bounds ids orphaned by refreshes.
    @State private var summaryCache: [UUID: Summary] = [:]
    @State private var computingIds: Set<UUID> = []

    private var summary: Summary? { summaryCache[shares.id] }
    private var isComputing: Bool { computingIds.contains(shares.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
                quickStatsSection

                if isComputing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Analyzing files...")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                    .padding()
                } else if let summary {
                    Divider().background(SeeleColors.surfaceSecondary)
                    fileTypeSection(summary)
                    Divider().background(SeeleColors.surfaceSecondary)

                    if summary.hasAudio {
                        bitrateSection(summary)
                        Divider().background(SeeleColors.surfaceSecondary)
                    }

                    largestFilesSection(summary)

                    if summary.hasFiles {
                        treemapSection(summary)
                    }
                }
            }
            .padding(SeeleSpacing.lg)
        }
        .background(SeeleColors.surface)
        .onAppear {
            computeStatsIfNeeded()
        }
        .onChange(of: shares.id) { _, _ in
            computeStatsIfNeeded()
        }
    }

    private func computeStatsIfNeeded() {
        let id = shares.id
        guard summaryCache[id] == nil, !computingIds.contains(id) else { return }

        computingIds.insert(id)
        let folders = shares.folders

        Task.detached(priority: .userInitiated) {
            let computed = Self.computeStats(from: folders)

            await MainActor.run {
                if summaryCache.count > 8 {
                    summaryCache.removeAll(keepingCapacity: true)
                }
                summaryCache[id] = computed
                computingIds.remove(id)
            }
        }
    }

    nonisolated private static func computeStats(from folders: [SharedFile]) -> Summary {
        let files = collectFilesNonRecursive(from: folders)
        let audio = files.filter { $0.isAudioFile }
        let top = files
            .sorted { $0.size > $1.size }
            .prefix(5)
            .map { ($0.displayFilename, $0.size) }
        let (typeEntries, typeTotalSize) = FileTypeDistribution.summarize(files: files)

        return Summary(
            typeEntries: typeEntries,
            typeTotalSize: typeTotalSize,
            bitrateBuckets: BitrateDistribution.summarize(files: audio),
            hasAudio: !audio.isEmpty,
            topFiles: Array(top),
            treemapFiles: Array(files.prefix(50)),
            hasFiles: !files.isEmpty
        )
    }

    nonisolated private static func collectFilesNonRecursive(from folders: [SharedFile]) -> [SharedFile] {
        var result: [SharedFile] = []
        var stack = folders

        while let current = stack.popLast() {
            if current.isDirectory {
                if let children = current.children {
                    stack.append(contentsOf: children)
                }
            } else {
                result.append(current)
            }
        }

        return result
    }

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Overview")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: SeeleSpacing.md) {
                StatCard(title: "Files", value: "\(shares.totalFiles)", icon: "doc.fill", color: SeeleColors.accent)
                StatCard(title: "Folders", value: "\(shares.folders.count)", icon: "folder.fill", color: SeeleColors.warning)
                StatCard(title: "Total Size", value: shares.totalSize.formattedBytes, icon: "externaldrive.fill", color: SeeleColors.info)
                StatCard(title: "Avg Size", value: (shares.totalSize / UInt64(max(shares.totalFiles, 1))).formattedBytes, icon: "chart.bar.fill", color: SeeleColors.success)
            }
        }
    }

    private func fileTypeSection(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("File Types")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            FileTypeDistribution(entries: summary.typeEntries, allFilesSize: summary.typeTotalSize)
        }
    }

    private func bitrateSection(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Audio Quality")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            BitrateDistribution(buckets: summary.bitrateBuckets)
        }
    }

    private func largestFilesSection(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Largest Files")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            SizeComparisonBars(items: summary.topFiles)
        }
    }

    private func treemapSection(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Size Distribution")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            FileTreemap(files: summary.treemapFiles)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: SeeleSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: SeeleSpacing.iconSize))
                    .foregroundStyle(color)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(value)
                        .font(SeeleTypography.headline)
                        .foregroundStyle(SeeleColors.textPrimary)
                    Text(title)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                Spacer()
            }
        }
        .padding(SeeleSpacing.md)
        .background(SeeleColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("\(title): \(value)")
    }
}

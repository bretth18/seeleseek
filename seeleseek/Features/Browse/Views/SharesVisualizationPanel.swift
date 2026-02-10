import SwiftUI

struct SharesVisualizationPanel: View {
    let shares: UserShares

    @State private var cachedAllFiles: [SharedFile]?
    @State private var cachedAudioFiles: [SharedFile]?
    @State private var cachedTopFiles: [(String, UInt64)]?
    @State private var isComputing = false

    private var allFiles: [SharedFile] {
        cachedAllFiles ?? []
    }

    private var audioFiles: [SharedFile] {
        cachedAudioFiles ?? []
    }

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
                } else if cachedAllFiles != nil {
                    Divider().background(SeeleColors.surfaceSecondary)
                    fileTypeSection
                    Divider().background(SeeleColors.surfaceSecondary)

                    if !audioFiles.isEmpty {
                        bitrateSection
                        Divider().background(SeeleColors.surfaceSecondary)
                    }

                    largestFilesSection

                    if !allFiles.isEmpty {
                        treemapSection
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
            cachedAllFiles = nil
            cachedAudioFiles = nil
            cachedTopFiles = nil
            computeStatsIfNeeded()
        }
    }

    private func computeStatsIfNeeded() {
        guard cachedAllFiles == nil && !isComputing else { return }

        isComputing = true
        let folders = shares.folders

        Task.detached(priority: .userInitiated) {
            let files = Self.collectFilesNonRecursive(from: folders)
            let audio = files.filter { $0.isAudioFile }
            let top = files
                .sorted { $0.size > $1.size }
                .prefix(5)
                .map { ($0.displayFilename, $0.size) }

            await MainActor.run {
                cachedAllFiles = files
                cachedAudioFiles = audio
                cachedTopFiles = Array(top)
                isComputing = false
            }
        }
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

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: SeeleSpacing.md) {
                StatCard(title: "Files", value: "\(shares.totalFiles)", icon: "doc.fill", color: SeeleColors.accent)
                StatCard(title: "Folders", value: "\(shares.folders.count)", icon: "folder.fill", color: SeeleColors.warning)
                StatCard(title: "Total Size", value: ByteFormatter.format(Int64(shares.totalSize)), icon: "externaldrive.fill", color: SeeleColors.info)
                StatCard(title: "Avg Size", value: ByteFormatter.format(Int64(shares.totalSize / UInt64(max(shares.totalFiles, 1)))), icon: "chart.bar.fill", color: SeeleColors.success)
            }
        }
    }

    private var fileTypeSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("File Types")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
            FileTypeDistribution(files: allFiles)
        }
    }

    private var bitrateSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Audio Quality")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
            BitrateDistribution(files: audioFiles)
        }
    }

    private var largestFilesSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Largest Files")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
            SizeComparisonBars(items: cachedTopFiles ?? [])
        }
    }

    private var treemapSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Size Distribution")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)
            FileTreemap(files: Array(allFiles.prefix(50)))
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
    }
}

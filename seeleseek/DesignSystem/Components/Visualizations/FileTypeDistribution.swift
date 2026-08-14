import SwiftUI
import SeeleseekCore

struct FileTypeDistribution: View {
    struct Entry: Equatable, Sendable {
        let type: String
        let count: Int
        let size: UInt64
    }

    /// Top extensions by size; allFilesSize covers ALL files so the bar
    /// leaves a gap for types past the top 8. Precomputed off-main by the
    /// caller.
    let entries: [Entry]
    let allFilesSize: UInt64

    // nonisolated: runs in the panel's detached stats task (app default is MainActor).
    nonisolated static func summarize(files: [SharedFile]) -> (entries: [Entry], allFilesSize: UInt64) {
        var grouped: [String: (count: Int, size: UInt64)] = [:]
        var total: UInt64 = 0

        for file in files {
            let fileExtension = file.fileExtension
            let ext = fileExtension.isEmpty ? "other" : fileExtension
            grouped[ext, default: (0, 0)].count += 1
            grouped[ext, default: (0, 0)].size += file.size
            total += file.size
        }

        let top = grouped
            .sorted { $0.value.size > $1.value.size }
            .prefix(8)
            .map { Entry(type: $0.key, count: $0.value.count, size: $0.value.size) }
        return (top, total)
    }

    private var distribution: [(type: String, count: Int, size: UInt64, color: Color)] {
        entries.map { (type: $0.type, count: $0.count, size: $0.size, color: colorForType($0.type)) }
    }

    private var totalSize: UInt64 {
        max(allFilesSize, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            // Stacked bar
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(distribution, id: \.type) { item in
                        let ratio = CGFloat(item.size) / CGFloat(totalSize)
                        let width = geometry.size.width * ratio

                        Rectangle()
                            .fill(item.color)
                            .frame(width: max(width.isFinite ? width - 1 : 2, 2))
                    }
                }
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            // The legend below carries the same data in spoken form.
            .accessibilityHidden(true)

            // Legend
            FlowLayout(spacing: SeeleSpacing.sm) {
                ForEach(distribution, id: \.type) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)

                        Text(item.type.uppercased())
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textSecondary)

                        Text("\(item.count)")
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                    .padding(.horizontal, SeeleSpacing.sm)
                    .padding(.vertical, SeeleSpacing.xxs)
                    .background(SeeleColors.surfaceSecondary)
                    .clipShape(Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityLabel("\(item.type.uppercased()): \(item.count) files, \(item.size.formattedBytes)")
                }
            }
        }
    }

    private func colorForType(_ type: String) -> Color {
        SeeleColors.fileType(for: type)
    }
}

#Preview {
    FileTypeDistribution(entries: [], allFilesSize: 1)
        .frame(width: 400)
        .padding()
        .background(SeeleColors.background)
}

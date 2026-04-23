import SwiftUI
import SeeleseekCore

struct FileTypeDistribution: View {
    let files: [SharedFile]

    private var distribution: [(type: String, count: Int, size: UInt64, color: Color)] {
        var grouped: [String: (count: Int, size: UInt64)] = [:]

        for file in files {
            let ext = file.fileExtension.isEmpty ? "other" : file.fileExtension.lowercased()
            grouped[ext, default: (0, 0)].count += 1
            grouped[ext, default: (0, 0)].size += file.size
        }

        return grouped
            .sorted { $0.value.size > $1.value.size }
            .prefix(8)
            .map { (type: $0.key, count: $0.value.count, size: $0.value.size, color: colorForType($0.key)) }
    }

    private var totalSize: UInt64 {
        max(files.reduce(0) { $0 + $1.size }, 1)
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
                }
            }
        }
    }

    private func colorForType(_ type: String) -> Color {
        SeeleColors.fileType(for: type)
    }
}

#Preview {
    FileTypeDistribution(files: [])
        .frame(width: 400)
        .padding()
        .background(SeeleColors.background)
}

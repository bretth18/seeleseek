import SwiftUI

// MARK: - File Size Treemap

/// Displays files as a treemap where size represents file size
struct FileTreemap: View {
    let files: [SharedFile]
    let onFileSelected: ((SharedFile) -> Void)?

    init(files: [SharedFile], onFileSelected: ((SharedFile) -> Void)? = nil) {
        self.files = files
        self.onFileSelected = onFileSelected
    }

    var body: some View {
        GeometryReader { geometry in
            let rects = calculateTreemap(
                files: files,
                in: CGRect(origin: .zero, size: geometry.size)
            )

            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                    let file = files[index]

                    TreemapCell(
                        file: file,
                        rect: rect,
                        color: colorForFileType(file.fileExtension)
                    )
                    .onTapGesture {
                        onFileSelected?(file)
                    }
                }
            }
        }
    }

    private func calculateTreemap(files: [SharedFile], in rect: CGRect) -> [CGRect] {
        guard !files.isEmpty else { return [] }

        let sortedFiles = files.sorted { $0.size > $1.size }
        let totalSize = sortedFiles.reduce(0) { $0 + $1.size }

        var rects: [CGRect] = []
        var remainingRect = rect

        for file in sortedFiles {
            let ratio = CGFloat(file.size) / CGFloat(max(totalSize, 1))
            let area = remainingRect.width * remainingRect.height * ratio

            // Decide split direction based on aspect ratio
            let isHorizontalSplit = remainingRect.width > remainingRect.height

            var fileRect: CGRect

            if isHorizontalSplit {
                let width = min(area / remainingRect.height, remainingRect.width)
                fileRect = CGRect(
                    x: remainingRect.minX,
                    y: remainingRect.minY,
                    width: width,
                    height: remainingRect.height
                )
                remainingRect = CGRect(
                    x: remainingRect.minX + width,
                    y: remainingRect.minY,
                    width: remainingRect.width - width,
                    height: remainingRect.height
                )
            } else {
                let height = min(area / remainingRect.width, remainingRect.height)
                fileRect = CGRect(
                    x: remainingRect.minX,
                    y: remainingRect.minY,
                    width: remainingRect.width,
                    height: height
                )
                remainingRect = CGRect(
                    x: remainingRect.minX,
                    y: remainingRect.minY + height,
                    width: remainingRect.width,
                    height: remainingRect.height - height
                )
            }

            rects.append(fileRect)
        }

        return rects
    }

    private func colorForFileType(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "mp3", "flac", "ogg", "m4a", "aac", "wav":
            return SeeleColors.accent
        case "mp4", "mkv", "avi", "mov":
            return SeeleColors.info
        case "jpg", "jpeg", "png", "gif":
            return SeeleColors.success
        case "zip", "rar", "7z":
            return SeeleColors.warning
        default:
            return SeeleColors.textTertiary
        }
    }
}

struct TreemapCell: View {
    let file: SharedFile
    let rect: CGRect
    let color: Color

    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(isHovered ? 0.9 : 0.7))
                .frame(width: rect.width - 2, height: rect.height - 2)

            if rect.width > 60 && rect.height > 40 {
                VStack(spacing: 2) {
                    Text(file.displayFilename)
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(ByteFormatter.format(Int64(file.size)))
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(4)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - File Type Distribution

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
        files.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            // Stacked bar
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(distribution, id: \.type) { item in
                        let ratio = CGFloat(item.size) / CGFloat(max(totalSize, 1))

                        Rectangle()
                            .fill(item.color)
                            .frame(width: max(geometry.size.width * ratio - 1, 2))
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SeeleColors.surfaceSecondary)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func colorForType(_ type: String) -> Color {
        switch type {
        case "mp3": return Color(hex: 0xE53935)
        case "flac": return Color(hex: 0x8E24AA)
        case "ogg": return Color(hex: 0x5E35B1)
        case "m4a", "aac": return Color(hex: 0x3949AB)
        case "wav": return Color(hex: 0x1E88E5)
        case "mp4", "mkv": return Color(hex: 0x00ACC1)
        case "jpg", "png": return Color(hex: 0x43A047)
        case "zip", "rar": return Color(hex: 0xFDD835)
        default: return Color(hex: 0x757575)
        }
    }
}

// MARK: - Bitrate Distribution Chart

struct BitrateDistribution: View {
    let files: [SharedFile]

    private var buckets: [(range: String, count: Int)] {
        let ranges: [(String, ClosedRange<UInt32>)] = [
            ("< 128", 0...127),
            ("128", 128...191),
            ("192", 192...255),
            ("256", 256...319),
            ("320", 320...320),
            ("> 320", 321...10000)
        ]

        return ranges.map { label, range in
            let count = files.filter { file in
                guard let bitrate = file.bitrate else { return false }
                return range.contains(bitrate)
            }.count

            return (range: label, count: count)
        }
    }

    private var maxCount: Int {
        buckets.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text("Bitrate Distribution (kbps)")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(buckets, id: \.range) { bucket in
                    VStack(spacing: 4) {
                        Text("\(bucket.count)")
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textTertiary)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(bucket.range == "320" ? SeeleColors.success : SeeleColors.accent.opacity(0.7))
                            .frame(height: CGFloat(bucket.count) / CGFloat(maxCount) * 60)

                        Text(bucket.range)
                            .font(SeeleTypography.caption2)
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > (proposal.width ?? .infinity) {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }

        return (positions, CGSize(width: maxWidth, height: currentY + lineHeight))
    }
}

// MARK: - Audio Waveform Visualization (decorative)

struct AudioWaveform: View {
    let isPlaying: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let bars = 20
                let barWidth = size.width / CGFloat(bars)
                let maxHeight = size.height

                for i in 0..<bars {
                    let x = CGFloat(i) * barWidth
                    let heightFactor = isPlaying
                        ? (0.3 + 0.7 * sin(phase + CGFloat(i) * 0.5) * sin(phase * 2 + CGFloat(i) * 0.3))
                        : 0.2

                    let height = max(4, maxHeight * CGFloat(heightFactor))
                    let y = (size.height - height) / 2

                    let rect = CGRect(x: x + 1, y: y, width: barWidth - 2, height: height)
                    let path = RoundedRectangle(cornerRadius: 2).path(in: rect)

                    context.fill(path, with: .color(SeeleColors.accent))
                }
            }
        }
        .onAppear {
            if isPlaying {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
            }
        }
    }
}

// MARK: - Size Comparison Bars

struct SizeComparisonBars: View {
    let items: [(label: String, size: UInt64)]

    private var maxSize: UInt64 {
        items.map(\.size).max() ?? 1
    }

    var body: some View {
        VStack(spacing: SeeleSpacing.sm) {
            ForEach(items, id: \.label) { item in
                HStack(spacing: SeeleSpacing.sm) {
                    Text(item.label)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                        .frame(width: 100, alignment: .leading)

                    GeometryReader { geometry in
                        let ratio = CGFloat(item.size) / CGFloat(maxSize)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SeeleColors.surfaceSecondary)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [SeeleColors.accent, SeeleColors.accent.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * ratio)
                        }
                    }
                    .frame(height: 20)

                    Text(ByteFormatter.format(Int64(item.size)))
                        .font(SeeleTypography.mono)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
    }
}

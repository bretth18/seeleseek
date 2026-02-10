import SwiftUI

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
        guard !files.isEmpty, rect.width > 0, rect.height > 0 else { return [] }

        let sortedFiles = files.sorted { $0.size > $1.size }
        let totalSize = max(sortedFiles.reduce(0) { $0 + $1.size }, 1)

        var rects: [CGRect] = []
        var remainingRect = rect

        for file in sortedFiles {
            guard remainingRect.width > 1, remainingRect.height > 1 else {
                rects.append(CGRect(x: remainingRect.minX, y: remainingRect.minY, width: 1, height: 1))
                continue
            }

            let ratio = CGFloat(file.size) / CGFloat(totalSize)
            let area = max(remainingRect.width * remainingRect.height * ratio, 1)

            let isHorizontalSplit = remainingRect.width > remainingRect.height

            var fileRect: CGRect

            if isHorizontalSplit {
                let divisor = max(remainingRect.height, 1)
                let width = max(min(area / divisor, remainingRect.width), 1)
                fileRect = CGRect(
                    x: remainingRect.minX,
                    y: remainingRect.minY,
                    width: width,
                    height: remainingRect.height
                )
                remainingRect = CGRect(
                    x: remainingRect.minX + width,
                    y: remainingRect.minY,
                    width: max(remainingRect.width - width, 0),
                    height: remainingRect.height
                )
            } else {
                let divisor = max(remainingRect.width, 1)
                let height = max(min(area / divisor, remainingRect.height), 1)
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
                    height: max(remainingRect.height - height, 0)
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

    private var safeWidth: CGFloat {
        let w = rect.width
        return w.isFinite && w > 0 ? max(w, 1) : 1
    }

    private var safeHeight: CGFloat {
        let h = rect.height
        return h.isFinite && h > 0 ? max(h, 1) : 1
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(isHovered ? 0.9 : 0.7))
                .frame(width: max(safeWidth - 2, 1), height: max(safeHeight - 2, 1))

            if safeWidth > 60 && safeHeight > 40 {
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
        .frame(width: safeWidth, height: safeHeight)
        .offset(x: rect.minX.isFinite ? rect.minX : 0, y: rect.minY.isFinite ? rect.minY : 0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    FileTreemap(files: [])
        .frame(width: 400, height: 300)
        .background(SeeleColors.background)
}

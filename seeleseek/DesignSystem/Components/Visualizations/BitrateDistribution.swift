import SwiftUI

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
        max(buckets.map(\.count).max() ?? 1, 1)
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
                            .frame(height: max(CGFloat(bucket.count) / CGFloat(maxCount) * 60, 2))

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

#Preview {
    BitrateDistribution(files: [])
        .frame(width: 400)
        .padding()
        .background(SeeleColors.background)
}

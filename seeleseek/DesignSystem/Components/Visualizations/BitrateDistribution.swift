import SwiftUI
import SeeleseekCore

struct BitrateDistribution: View {
    struct Bucket: Equatable, Sendable {
        let range: String
        let count: Int
    }

    /// Precomputed off-main by the caller: bucketing in `body` re-filtered
    /// the full file list six times per render.
    let buckets: [Bucket]

    static func summarize(files: [SharedFile]) -> [Bucket] {
        let ranges: [(String, ClosedRange<UInt32>)] = [
            ("< 128", 0...127),
            ("128", 128...191),
            ("192", 192...255),
            ("256", 256...319),
            ("320", 320...320),
            ("> 320", 321...10000)
        ]

        var counts = [Int](repeating: 0, count: ranges.count)
        for file in files {
            guard let bitrate = file.bitrate else { continue }
            if let index = ranges.firstIndex(where: { $0.1.contains(bitrate) }) {
                counts[index] += 1
            }
        }
        return zip(ranges, counts).map { Bucket(range: $0.0, count: $1) }
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityLabel("\(bucket.range) kilobits per second: \(bucket.count) files")
                }
            }
            .frame(height: 100)
        }
    }
}

#Preview {
    BitrateDistribution(buckets: BitrateDistribution.summarize(files: []))
        .frame(width: 400)
        .padding()
        .background(SeeleColors.background)
}

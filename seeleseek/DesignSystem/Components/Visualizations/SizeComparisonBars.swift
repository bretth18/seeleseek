import SwiftUI

struct SizeComparisonBars: View {
    let items: [(label: String, size: UInt64)]

    private var maxSize: UInt64 {
        max(items.map(\.size).max() ?? 1, 1)
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

#Preview {
    SizeComparisonBars(items: [
        (label: "Music", size: 1_500_000_000),
        (label: "Videos", size: 800_000_000),
        (label: "Images", size: 200_000_000),
    ])
    .frame(width: 400)
    .padding()
    .background(SeeleColors.background)
}

import SwiftUI

struct ConnectionRingView: View {
    let active: Int
    let total: Int
    let maxDisplay: Int

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return min(Double(active) / Double(min(total, maxDisplay)), 1.0)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(SeeleColors.surfaceSecondary, lineWidth: 6)

            // Active ring
            Circle()
                .trim(from: 0, to: percentage)
                .stroke(
                    SeeleColors.success,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: percentage)

            // Center text
            VStack(spacing: 0) {
                Text("\(active)")
                    .font(SeeleTypography.title2)
                    .foregroundStyle(SeeleColors.textPrimary)
            }
        }
    }
}

struct TransferRatioView: View {
    let downloaded: Int
    let uploaded: Int

    private var total: Int { downloaded + uploaded }
    private var downloadRatio: Double {
        guard total > 0 else { return 0.5 }
        return Double(downloaded) / Double(total)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Download portion
                Circle()
                    .trim(from: 0, to: downloadRatio)
                    .stroke(SeeleColors.success, lineWidth: 8)
                    .rotationEffect(.degrees(-90))

                // Upload portion
                Circle()
                    .trim(from: downloadRatio, to: 1)
                    .stroke(SeeleColors.accent, lineWidth: 8)
                    .rotationEffect(.degrees(-90))

                // Center
                VStack(spacing: 0) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: SeeleSpacing.iconSizeMedium))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }
        }
    }
}

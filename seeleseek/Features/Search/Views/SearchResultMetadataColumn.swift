import SwiftUI
import SeeleseekCore

/// Right (fixed-width) column of a search row: quality chip, tech-spec
/// columns, and the peer-state line. Depends only on `result`.
struct SearchResultMetadataColumn: View {
    let result: SearchResult

    var body: some View {
        let tier = QualityScale.tier(for: result)
        VStack(alignment: .trailing, spacing: SeeleSpacing.xxs) {
            HStack(spacing: SeeleSpacing.sm) {
                StandardMetadataBadge(tier.label, color: tier.color)
                    .rowHelp(tier.helpText)
                    .frame(width: SearchResultRowLayout.qualityChipSlotWidth, alignment: .trailing)
                    .accessibilityLabel(tier.helpText)

                techSpecColumns
            }

            secondaryMetadata
        }
    }

    private var techSpecColumns: some View {
        HStack(spacing: SeeleSpacing.xs) {
            statCell(
                width: SearchResultStatColumn.formatBitrate.width,
                text: formatBitrateText,
                color: SeeleColors.textSecondary
            )
            statCell(
                width: SearchResultStatColumn.sampleBitDepth.width,
                text: sampleBitDepthText,
                color: SeeleColors.textTertiary
            )
            statCell(
                width: SearchResultStatColumn.duration.width,
                text: result.formattedDuration ?? "",
                color: SeeleColors.textTertiary
            )
            statCell(
                width: SearchResultStatColumn.size.width,
                text: result.formattedSize,
                color: SeeleColors.textTertiary
            )
        }
    }

    private func statCell(width: CGFloat, text: String, color: Color) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(SeeleTypography.monoSmall)
            .foregroundStyle(text.isEmpty ? SeeleColors.textTertiary : color)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    private var formatBitrateText: String {
        let ext = result.fileExtension.uppercased()
        if let bitrate = result.bitrate, bitrate > 0 {
            return "\(ext) \(bitrate)"
        }
        return ext
    }

    private var sampleBitDepthText: String {
        guard let sampleRate = result.sampleRate, sampleRate > 0 else { return "" }
        let khz = Double(sampleRate) / 1000.0
        let base = khz == khz.rounded() ? "\(Int(khz))" : String(format: "%.1f", khz)
        if let bd = result.bitDepth, bd > 0 { return "\(base)/\(bd)" }
        return "\(base) kHz"
    }

    /// Line 2 of the metadata column. Real peer state — no estimates.
    @ViewBuilder
    private var secondaryMetadata: some View {
        if !result.freeSlots {
            HStack(spacing: SeeleSpacing.xxs) {
                Image(systemName: "hourglass")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                Text("Queue \(result.queueLength)")
                    .font(SeeleTypography.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(SeeleColors.warning)
        } else if !result.isPrivate {
            HStack(spacing: SeeleSpacing.xxs) {
                Circle()
                    .fill(SeeleColors.success)
                    .frame(
                        width: SeeleSpacing.statusDotSmall,
                        height: SeeleSpacing.statusDotSmall
                    )
                Text("Available")
                    .font(SeeleTypography.caption)
            }
            .foregroundStyle(SeeleColors.success)
        } else {
            HStack(spacing: SeeleSpacing.xxs) {
                Circle()
                    .fill(SeeleColors.warning)
                    .frame(
                        width: SeeleSpacing.statusDotSmall,
                        height: SeeleSpacing.statusDotSmall
                    )
                Text("Private")
                    .font(SeeleTypography.caption)
            }
            .foregroundStyle(SeeleColors.warning)
        }
    }
}

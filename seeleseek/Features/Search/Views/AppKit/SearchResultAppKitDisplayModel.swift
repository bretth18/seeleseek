import AppKit
import SeeleseekCore
import SwiftUI

/// Precomputed strings and colors for an AppKit search row. Built once per
/// `configure` so reuse never re-runs `displayFilename.split` or quality math.
struct SearchResultAppKitDisplayModel: Equatable {
    let resultID: UUID
    let displayFilename: String
    let username: String
    let peerSpeedText: String
    let peerSpeedColor: NSColor
    let folderText: String
    let glyphName: String
    let glyphTint: NSColor
    let qualityLabel: String
    let qualityColor: NSColor
    let formatBitrateText: String
    let sampleBitDepthText: String
    let durationText: String
    let sizeText: String
    let availabilityText: String
    let availabilityColor: NSColor

    static func make(from result: SearchResult) -> SearchResultAppKitDisplayModel {
        let tier = QualityScale.tier(for: result)
        let sampleBitDepth = sampleBitDepthText(for: result)
        let availability = availability(for: result)

        return SearchResultAppKitDisplayModel(
            resultID: result.id,
            displayFilename: displayFilename(for: result.filename),
            username: result.username,
            peerSpeedText: peerSpeedText(for: result),
            peerSpeedColor: peerSpeedColor(for: result),
            folderText: folderText(for: result),
            glyphName: glyphName(for: result),
            glyphTint: glyphTint(for: result),
            qualityLabel: tier.label,
            qualityColor: NSColor(tier.color),
            formatBitrateText: formatBitrateText(for: result),
            sampleBitDepthText: sampleBitDepth,
            durationText: result.formattedDuration ?? "",
            sizeText: result.formattedSize,
            availabilityText: availability.text,
            availabilityColor: availability.color
        )
    }

    // MARK: - Filename (single split, not `SearchResult.displayFilename`)

    private static func displayFilename(for filename: String) -> String {
        if let lastComponent = filename.split(separator: "\\").last {
            return String(lastComponent)
        }
        return filename
    }

    private static func folderText(for result: SearchResult) -> String {
        let compact = FolderPathLabel.compact(result.folderPath)
        return compact.isEmpty ? "—" : compact
    }

    private static func glyphName(for result: SearchResult) -> String {
        if result.isLossless { return "waveform" }
        if result.isAudioFile { return "music.note" }
        if result.isImageFile { return "photo" }
        if result.isVideoFile { return "video" }
        return "doc"
    }

    private static func glyphTint(for result: SearchResult) -> NSColor {
        if result.isLossless { return NSColor(SeeleColors.success) }
        if result.isAudioFile { return NSColor(SeeleColors.accent) }
        return NSColor(SeeleColors.textTertiary)
    }

    private static func formatBitrateText(for result: SearchResult) -> String {
        let ext = fileExtension(from: result.filename)
        if let bitrate = result.bitrate, bitrate > 0 {
            return ext.isEmpty ? "\(bitrate)" : "\(ext.uppercased()) \(bitrate)"
        }
        return ext.isEmpty ? "—" : ext.uppercased()
    }

    private static func fileExtension(from filename: String) -> String {
        let display = displayFilename(for: filename)
        let components = display.split(separator: ".")
        if components.count > 1, let ext = components.last {
            return String(ext).lowercased()
        }
        return ""
    }

    private static func sampleBitDepthText(for result: SearchResult) -> String {
        guard let sampleRate = result.sampleRate, sampleRate > 0 else { return "" }
        let khz = Double(sampleRate) / 1000.0
        let base = khz == khz.rounded() ? "\(Int(khz))" : String(format: "%.1f", khz)
        if let bd = result.bitDepth, bd > 0 { return "\(base)/\(bd)" }
        return "\(base) kHz"
    }

    private static func peerSpeedText(for result: SearchResult) -> String {
        let bytesPerSecond = UInt64(result.uploadSpeed)
        guard bytesPerSecond > 0 else { return "unknown" }
        return bytesPerSecond.formattedBytes + "/s"
    }

    private static func peerSpeedColor(for result: SearchResult) -> NSColor {
        let bps = result.uploadSpeed
        if bps == 0 { return NSColor(SeeleColors.textTertiary) }
        if bps >= 1_000_000 { return NSColor(SeeleColors.success) }
        if bps >= 200_000 { return NSColor(SeeleColors.info) }
        return NSColor(SeeleColors.warning)
    }

    private static func availability(for result: SearchResult) -> (text: String, color: NSColor) {
        if !result.freeSlots {
            return ("Queue \(result.queueLength)", NSColor(SeeleColors.warning))
        }
        if !result.isPrivate {
            return ("Available", NSColor(SeeleColors.success))
        }
        return ("Private", NSColor(SeeleColors.warning))
    }
}

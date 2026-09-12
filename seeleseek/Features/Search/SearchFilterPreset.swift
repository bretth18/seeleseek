import Foundation

struct SearchFilterPreset: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var name: String
    var extensions: Set<String> = []
    var minBitrate: Int? = nil
    var minSampleRate: Int? = nil
    var minBitDepth: Int? = nil

    /// A pill with no constraints would read as active whenever the
    /// filters are clear, so the bar only shows complete ones.
    var isComplete: Bool {
        !name.isEmpty && (!extensions.isEmpty || minBitrate != nil || minSampleRate != nil || minBitDepth != nil)
    }

    static let defaults: [SearchFilterPreset] = [
        SearchFilterPreset(name: "MP3 320", extensions: ["mp3"], minBitrate: 320),
        SearchFilterPreset(name: "FLAC", extensions: ["flac"]),
        SearchFilterPreset(name: "Lossless", extensions: ["flac", "wav", "aiff", "alac", "ape"]),
        SearchFilterPreset(name: "Hi-Res", extensions: ["flac", "wav", "aiff", "alac"], minSampleRate: 96_000, minBitDepth: 24),
    ]

    /// "JPG, .jpeg png" → ["jpg", "jpeg", "png"].
    static func parseExtensions(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                .filter { !$0.isEmpty }
        )
    }
}

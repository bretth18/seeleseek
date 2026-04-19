import SwiftUI
import AVFoundation

/// 30-second auto-stopping preview player shared by TransferRow and
/// HistoryRow. Owns the `AVAudioPlayer` and the `isPlaying` flag so row
/// views don't each re-implement the same state machine.
@Observable
@MainActor
final class RowAudioPreview {
    static let previewDuration: TimeInterval = 30

    private(set) var isPlaying: Bool = false
    private var player: AVAudioPlayer?
    private var autoStopTask: Task<Void, Never>?

    func toggle(url: URL) {
        if isPlaying {
            stop()
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true

            autoStopTask?.cancel()
            autoStopTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.previewDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        autoStopTask?.cancel()
        autoStopTask = nil
        player?.stop()
        player = nil
        isPlaying = false
    }
}

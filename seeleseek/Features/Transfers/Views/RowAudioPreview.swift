import SwiftUI
import AVFoundation

/// App-wide audio preview coordinator. Holds at most one active
/// `AVAudioPlayer` so starting playback in any row stops whatever was
/// playing before — rows that ask via `isPlaying(url:)` reflect only
/// their own URL, and the previous row's button reverts to "play"
/// automatically. Lives on `AppState` (rather than as per-row `@State`)
/// so playback survives row scrolling, list re-sorts, and tab switches.
@Observable
@MainActor
final class RowAudioPreview {
    static let previewDuration: TimeInterval = 30

    private(set) var currentURL: URL?
    private var player: AVAudioPlayer?
    private var autoStopTask: Task<Void, Never>?

    func isPlaying(url: URL) -> Bool {
        currentURL == url
    }

    /// Start playback of `url`, replacing whatever's currently playing.
    /// If `url` is already the active preview, stops it instead.
    func toggle(url: URL) {
        if currentURL == url {
            stop()
            return
        }
        // Tear down the previous preview before starting the new one so
        // we never have overlapping audio across rows.
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
            currentURL = url

            autoStopTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.previewDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            currentURL = nil
        }
    }

    func stop() {
        autoStopTask?.cancel()
        autoStopTask = nil
        player?.stop()
        player = nil
        currentURL = nil
    }
}

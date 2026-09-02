import SwiftUI
import SeeleseekCore

/// Add-folder + rescan/progress row, self-observing.
///
/// This is deliberately its own view rather than inline in
/// `SharesSettingsSection`: `scanProgress` ticks once per shared folder
/// during a scan, and reading it in the parent's body invalidated the
/// whole section — including the `ForEach` over folders, which tore down
/// and rebuilt one `NSPopUpButton` per row on every tick. Measured at 13
/// folders: 14 section rebuilds and 182 row rebuilds inside ~400 ms.
/// Keeping the read down here means a progress tick re-renders this row
/// and nothing else.
struct SharesScanControl: View {
    @Environment(\.appState) private var appState

    private var shareManager: ShareManager {
        appState.networkClient.shareManager
    }

    private var shares: ShareState {
        appState.networkClient.shareManager.state
    }

    var body: some View {
        HStack {
            Button(action: showFolderPicker) {
                HStack(spacing: SeeleSpacing.xs) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                    Text("Add Folder")
                }
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.accent)
            }
            .buttonStyle(.plain)
            .help("Pick one or more folders on disk to share with peers.")

            Spacer()

            if shares.isScanning {
                scanProgressLabel
            } else {
                rescanButton
            }
        }
    }

    private var scanProgressLabel: some View {
        let percent = Int(shares.scanProgress * 100)
        return HStack(spacing: SeeleSpacing.xs) {
            ProgressView()
                .scaleEffect(0.6)
            Text("Scanning \(percent)%")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanning shared folders, \(percent) percent")
    }

    private var rescanButton: some View {
        Button(action: rescan) {
            HStack(spacing: SeeleSpacing.xs) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                Text("Rescan")
            }
            .font(SeeleTypography.caption)
            .foregroundStyle(SeeleColors.textSecondary)
        }
        .buttonStyle(.plain)
        .help("Re-read all shared folders and refresh the file index.")
    }

    private func rescan() {
        Task { await shareManager.rescanAll() }
    }

    private func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to share"
        panel.prompt = "Share"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            Task { await shareManager.addFolder(url) }
        }
    }
}

import SwiftUI
import SeeleseekCore

struct UpdatePromptSheet: View {
    @Bindable var updateState: UpdateState
    @Environment(\.dismissWindow) private var dismissWindow

    private func close() {
        updateState.showUpdatePrompt = false
        dismissWindow(id: "update-prompt")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            header
            releaseNotes
            Spacer(minLength: 0)
            buttons
        }
        .padding(SeeleSpacing.lg)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 380, idealHeight: 480)
        .background(SeeleColors.background)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SeeleSpacing.md) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(SeeleColors.accent)

            VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                Text("Update Available")
                    .font(SeeleTypography.title)
                    .foregroundStyle(SeeleColors.textPrimary)

                if let latest = updateState.latestVersion {
                    Text("Version \(latest) — you're on \(updateState.currentFullVersionFormatted)")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var releaseNotes: some View {
        if let notes = updateState.releaseNotes, !notes.isEmpty {
            ScrollView {
                Text(notes)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SeeleSpacing.md)
            }
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        } else {
            Text("No release notes available.")
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }

    private var buttons: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Button("Skip This Version") {
                updateState.skipCurrentVersion()
                close()
            }
            .buttonStyle(.plain)
            .foregroundStyle(SeeleColors.textSecondary)

            Spacer()

            Button("Remind Me Later") {
                updateState.remindLater()
                close()
            }
            .keyboardShortcut(.cancelAction)

            if updateState.isDownloading {
                downloadProgress
            } else {
                Button("Download & Install") {
                    Task { await updateState.downloadAndInstall() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(updateState.latestPkgURL == nil)
            }
        }
    }

    private var downloadProgress: some View {
        HStack(spacing: SeeleSpacing.sm) {
            ProgressView(value: updateState.downloadProgress ?? 0)
            {
                Text(progressLabel)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
            }
            .progressViewStyle(.linear)
            .frame(width: 140)
            
        
        }
    }

    private var progressLabel: String {
        if let p = updateState.downloadProgress {
            return "\(Int(p * 100))%"
        }
        return "Starting…"
    }
}

#if DEBUG
@MainActor
private func previewUpdateState(
    latestVersion: String? = "1.2.0",
    releaseNotes: String? = """
    ## What's New

    - Fixed STUN external IP discovery (was sending requests in the wrong byte order).
    - Forced IPv4 on STUN queries so we get a usable Soulseek peer address.
    - Trimmed noisy debug logging in the NAT path.

    ## Fixes

    - Salvage lookup is now O(1) instead of O(history size).
    - Cancellation discipline audit — one retain cycle fixed in `PeerConnectionPool`.
    """,
    isDownloading: Bool = false,
    progress: Double? = nil,
    hasPkgURL: Bool = true
) -> UpdateState {
    let state = UpdateState()
    state.latestVersion = latestVersion
    state.releaseNotes = releaseNotes
    state.isDownloading = isDownloading
    state.downloadProgress = progress
    if hasPkgURL {
        state.latestPkgURL = URL(string: "https://example.com/seeleseek.pkg")
    }
    return state
}

#Preview("Update available") {
    UpdatePromptSheet(updateState: previewUpdateState())
}

#Preview("Downloading — starting") {
    UpdatePromptSheet(updateState: previewUpdateState(isDownloading: true, progress: nil))
}

#Preview("Downloading — 45%") {
    UpdatePromptSheet(updateState: previewUpdateState(isDownloading: true, progress: 0.45))
}

#Preview("Downloading — 95%") {
    UpdatePromptSheet(updateState: previewUpdateState(isDownloading: true, progress: 0.95))
}

#Preview("No release notes") {
    UpdatePromptSheet(updateState: previewUpdateState(releaseNotes: nil))
}

#Preview("No pkg asset") {
    UpdatePromptSheet(updateState: previewUpdateState(hasPkgURL: false))
}
#endif

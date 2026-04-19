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
                    Text("Version \(latest) — you're on \(updateState.currentFullVersion)")
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
                .progressViewStyle(.linear)
                .frame(width: 140)
            Text(progressLabel)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textSecondary)
        }
    }

    private var progressLabel: String {
        if let p = updateState.downloadProgress {
            return "\(Int(p * 100))%"
        }
        return "Starting…"
    }
}



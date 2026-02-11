import SwiftUI

struct UpdateSettingsSection: View {
    @Bindable var updateState: UpdateState

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            settingsHeader("Update")

            settingsGroup("Application") {
                settingsRow {
                    HStack {
                        Text("Current Version")
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)

                        Spacer()

                        Text(updateState.currentFullVersion)
                            .font(SeeleTypography.mono)
                            .foregroundStyle(SeeleColors.textSecondary)
                    }
                }

                settingsRow {
                    HStack {
                        Text("Check for Updates")
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)

                        Spacer()

                        if updateState.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Check Now") {
                                Task { await updateState.checkForUpdate() }
                            }
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.accent)
                            .buttonStyle(.plain)
                        }
                    }
                }

                settingsToggle("Check automatically on launch", isOn: Binding(
                    get: { updateState.autoCheckEnabled },
                    set: { updateState.autoCheckEnabled = $0 }
                ))

                if let lastCheck = updateState.lastCheckDate {
                    settingsRow {
                        HStack {
                            Text("Last Checked")
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textPrimary)

                            Spacer()

                            Text(lastCheck, style: .relative)
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textTertiary)
                            Text("ago")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }
                    }
                }
            }

            if let error = updateState.errorMessage {
                settingsGroup("Error") {
                    settingsRow {
                        HStack(spacing: SeeleSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(SeeleColors.error)
                            Text(error)
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.error)
                        }
                    }
                }
            }

            if updateState.updateAvailable {
                updateAvailableCard
            } else if !updateState.isChecking, updateState.lastCheckDate != nil, updateState.errorMessage == nil {
                settingsGroup("Status") {
                    settingsRow {
                        HStack(spacing: SeeleSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SeeleColors.success)
                            Text("You're running the latest version")
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var updateAvailableCard: some View {
        settingsGroup("Update Available") {
            settingsRow {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    HStack {
                        Text("Version \(updateState.latestVersion ?? "")")
                            .font(SeeleTypography.headline)
                            .foregroundStyle(SeeleColors.textPrimary)

                        Spacer()

                        if let url = updateState.latestReleaseURL {
                            Link(destination: url) {
                                Text("View on GitHub")
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.accent)
                            }
                        }
                    }

                    if let notes = updateState.releaseNotes, !notes.isEmpty {
                        Text(notes)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxHeight: 150)
                    }

                    Divider()

                    if updateState.isDownloading {
                        VStack(spacing: SeeleSpacing.xs) {
                            ProgressView(value: updateState.downloadProgress ?? 0)
                                .tint(SeeleColors.accent)

                            Text("Downloading... \(Int((updateState.downloadProgress ?? 0) * 100))%")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.textTertiary)
                        }
                    } else {
                        HStack {
                            Button("Download & Install") {
                                Task { await updateState.downloadAndInstall() }
                            }
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.accent)
                            .buttonStyle(.plain)

                            Spacer()

                            Button("Dismiss") {
                                updateState.dismissUpdate()
                            }
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

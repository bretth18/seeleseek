import SwiftUI
#if os(macOS)
import AppKit
#endif
import SeeleseekCore

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
                    // The caption and the version are separate texts.
                    // One element speaks them together.
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isStaticText)
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
                                .accessibilityLabel("Checking for updates")
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

                settingsToggle("Check automatically on launch", isOn: $updateState.autoCheckEnabled)

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
                        // The time and the word "ago" are separate
                        // texts. One element speaks them together.
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isStaticText)
                    }
                }
            }

            if let error = updateState.errorMessage {
                settingsGroup("Error") {
                    settingsRow {
                        HStack(spacing: SeeleSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(SeeleColors.error)
                                .accessibilityHidden(true)
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
                                .accessibilityHidden(true)
                            Text("You're running the latest version")
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    /// Removes leading markdown markers per line so VoiceOver does not
    /// speak "#" and "-" characters.
    static func spokenReleaseNotes(_ notes: String) -> String {
        notes
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var trimmed = line
                while let first = trimmed.first, first == " " {
                    trimmed = trimmed.dropFirst()
                }
                while let first = trimmed.first, first == "#" || first == "-" || first == "*" {
                    trimmed = trimmed.dropFirst()
                }
                while let first = trimmed.first, first == " " {
                    trimmed = trimmed.dropFirst()
                }
                return String(trimmed)
            }
            .joined(separator: "\n")
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
                            // VoiceOver must not speak raw markdown
                            // markers. The visual text is unchanged.
                            .accessibilityLabel(Self.spokenReleaseNotes(notes))
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
                        // The bar and the percent text describe one
                        // download. One element speaks them together.
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Downloading update")
                        .accessibilityValue("\(Int((updateState.downloadProgress ?? 0) * 100)) percent")
                    } else {
                        HStack {
                            Button("Download & Install") {
                                Task {
                                    guard let pkgURL = await updateState.downloadPkg() else {
                                        VoiceOverAnnouncer.shared.announce("Update download failed")
                                        return
                                    }
                                    #if os(macOS)
                                    NSWorkspace.shared.open(pkgURL)
                                    #endif
                                }
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

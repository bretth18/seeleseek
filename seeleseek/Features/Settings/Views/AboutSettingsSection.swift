import SwiftUI

struct AboutSettingsSection: View {
    private let projectURL = URL(string: "https://github.com/bretth18/seeleseek")
    private let licenseURL = URL(string: "https://github.com/bretth18/seeleseek/blob/main/LICENSE")

    private var appName: String {
        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
            return displayName
        }
        if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
            return bundleName
        }
        return "seeleseek"
    }

    private var copyright: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String, !value.isEmpty {
            return value
        }
        return "Copyright © 2026 The Virtuous Corporation"
    }

    var body: some View {
        settingsGroup("About") {
            settingsRow {
                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(appName)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Text(copyright)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)

                    Text("License: MIT")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .overlay(SeeleColors.border)
                .padding(.horizontal, SeeleSpacing.rowHorizontal)

            settingsRow {
                VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                    Text("Legal Notice")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)

                    Text("seeleseek is an independent, third-party client and is not affiliated with, endorsed by, or sponsored by Soulseek.")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)

                    Text("This software is provided for lawful use only. The project does not condone, encourage, or support copyright infringement or illegal file sharing.")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)

                    Text("You are solely responsible for how you use this application and for complying with all applicable laws, licenses, and terms in your jurisdiction.")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .overlay(SeeleColors.border)
                .padding(.horizontal, SeeleSpacing.rowHorizontal)

            settingsRow {
                HStack(alignment: .center, spacing: SeeleSpacing.xs) {
                    if let projectURL {
                        Link(destination: projectURL) {
                            Label("GitHub", systemImage: "link")
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()

                    if let licenseURL {
                        Link(destination: licenseURL) {
                            Label("License", systemImage: "doc.text")
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    VStack {
        AboutSettingsSection()
    }
    .padding(SeeleSpacing.lg)
    .background(SeeleColors.background)
}

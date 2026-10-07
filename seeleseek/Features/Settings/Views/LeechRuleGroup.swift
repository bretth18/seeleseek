import SwiftUI

struct LeechRuleGroup: View {
    @Bindable var leech: LeechDetector

    var body: some View {
        settingsGroup(nil) {
            settingsToggle("Detect leechers", isOn: $leech.settings.enabled)
            settingsCaption("Buddies are never checked.")

            Divider()

            Group {
                conditionRow

                branch(isLast: false) {
                    toggle("Deny downloads", isOn: Binding(
                        get: { leech.settings.deniesTransfers },
                        set: { leech.settings.denyDownloads = $0 }
                    ))
                    .disabled(leech.settings.blockUser)
                }
                branch(isLast: false) {
                    toggle("Send message", isOn: $leech.settings.sendMessage)
                }
                if leech.settings.sendMessage {
                    branch(isLast: false, hasTick: false) {
                        messageEditor
                    }
                }
                branch(isLast: true) {
                    toggle("Block user", isOn: $leech.settings.blockUser)
                }
            }
            .disabled(!leech.settings.enabled)
        }
    }

    private var conditionRow: some View {
        settingsRow {
            HStack(spacing: SeeleSpacing.sm) {
                Text("Sharing fewer than")
                thresholdField("Minimum shared files", value: $leech.settings.minSharedFiles)
                Text("files or")
                thresholdField("Minimum shared folders", value: $leech.settings.minSharedFolders)
                Text("folders")
                Spacer()
            }
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)
        }
    }

    private func thresholdField(_ label: String, value: Binding<UInt32>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(SeeleTextFieldStyle())
            .frame(width: 64)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(label)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityHidden(true)

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(SeeleToggleStyle())
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
            TextEditor(text: $leech.settings.customMessage)
                .accessibilityLabel("Leech message")
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(SeeleSpacing.sm)
                .background(SeeleColors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD / 2))
                .frame(height: 64)

            Text("Sent once per user. %files% and %folders% insert the minimums.")
                .font(SeeleTypography.caption2)
                .foregroundStyle(SeeleColors.textTertiary)

            HStack(spacing: SeeleSpacing.xs) {
                ForEach(LeechSettings.defaultMessages.indices, id: \.self) { index in
                    Button("Template \(index + 1)") {
                        leech.settings.customMessage = LeechSettings.defaultMessages[index]
                    }
                    .buttonStyle(.seeleSecondary(.small))
                    .help(LeechSettings.defaultMessages[index])
                    .accessibilityHint("Replaces the message")
                }
            }
        }
    }

    // MARK: - Branches

    private static let connectorWidth: CGFloat = 12

    private func branch<Content: View>(
        isLast: Bool,
        hasTick: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsRow {
            HStack(alignment: hasTick ? .center : .top, spacing: SeeleSpacing.sm) {
                BranchConnector(isLast: isLast, hasTick: hasTick)
                    .stroke(SeeleColors.border, lineWidth: 1)
                    .frame(width: Self.connectorWidth)
                    .padding(.vertical, -SeeleSpacing.rowVertical)
                    .accessibilityHidden(true)
                content()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// `├─`, `└─`, or a bare `│` when `hasTick` is false.
private nonisolated struct BranchConnector: Shape {
    var isLast: Bool
    var hasTick: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 0.5
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY))
        if hasTick {
            path.move(to: CGPoint(x: x, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}

#if DEBUG
#Preview {
    let leech = LeechDetector()
    leech.settings.enabled = true
    leech.settings.denyDownloads = true
    leech.settings.sendMessage = true
    return LeechRuleGroup(leech: leech)
        .padding()
        .frame(width: 500)
        .background(SeeleColors.background)
}
#endif

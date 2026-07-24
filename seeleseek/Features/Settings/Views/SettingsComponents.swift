import SwiftUI
import SeeleseekCore

// MARK: - Shared Settings Components

/// Section header for settings groups
func settingsHeader(_ title: String) -> some View {
    Text(title)
        .font(SeeleTypography.title)
        .foregroundStyle(SeeleColors.textPrimary)
}

/// Grouped settings section with title and bordered container
func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
        Text(title)
            .font(SeeleTypography.caption)
            .foregroundStyle(SeeleColors.textTertiary)

        VStack(spacing: 0) {
            content()
        }
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                .stroke(SeeleColors.border, lineWidth: 1)
        )
    }
}

/// Padded settings row
func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(.horizontal, SeeleSpacing.rowHorizontal)
        .padding(.vertical, SeeleSpacing.rowVertical)
        .background(SeeleColors.surface)
}

/// Toggle row with title
func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    settingsRow {
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
}

func settingsPicker<T: Hashable>(_ title: String, selection: Binding<T>, options: [T], optionLabel: @escaping (T) -> String) -> some View {
    settingsRow {
        HStack {
            Text(title)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityHidden(true)

            Spacer()

            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionLabel(option))
                        .tag(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }
}

/// Numeric text field row
func settingsNumberField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, placeholder: String = "") -> some View {
    settingsRow {
        HStack {
            Text(title)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityHidden(true)

            Spacer()

            TextField(placeholder, value: value, format: .number)
                .textFieldStyle(SeeleTextFieldStyle())
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }
}

/// Stepper row with title and value display
func settingsStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
    settingsRow {
        HStack {
            Text(title)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityHidden(true)

            Spacer()

            Stepper("", value: value, in: range)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityValue("\(value.wrappedValue)")

            Text("\(value.wrappedValue)")
                .font(SeeleTypography.mono)
                .foregroundStyle(SeeleColors.textPrimary)
                .frame(width: 24, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

/// Folder picker row with title, path display, and Choose button
func folderPicker(_ title: String, url: Binding<URL>) -> some View {
    settingsRow {
        HStack {
            Text(title)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityHidden(true)

            Spacer()
            Button {
                NSWorkspace.shared.open(url.wrappedValue)
            } label: {
                Text(url.wrappedValue.path)
                    .font(SeeleTypography.mono)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) folder")
            .accessibilityValue(url.wrappedValue.path)
            .accessibilityHint("Opens the folder in Finder")
            Button("Choose...") {
                #if os(macOS)
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.message = "Select \(title.lowercased()) folder"
                panel.prompt = "Select"
                panel.directoryURL = url.wrappedValue

                if panel.runModal() == .OK, let selectedURL = panel.url {
                    url.wrappedValue = selectedURL
                }
                #endif
            }
            .font(SeeleTypography.caption)
            .foregroundStyle(SeeleColors.accent)
            .buttonStyle(.plain)
            .accessibilityLabel("Choose \(title) folder")
        }
    }
}


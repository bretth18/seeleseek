import SwiftUI

/// Editable list of the quick-filter pills shown in the search bar. Rows
/// are summary-only so their width never depends on content; editing
/// happens in a fixed-width popover.
struct SearchPresetsEditor: View {
    @Bindable var settings: SettingsState
    @State private var editingID: UUID?

    var body: some View {
        settingsGroup("Filter Shortcuts") {
            ForEach($settings.searchFilterPresets) { $preset in
                SearchPresetRow(
                    preset: $preset,
                    isEditing: Binding(
                        get: { editingID == preset.id },
                        set: { editingID = $0 ? preset.id : nil }
                    ),
                    isFirst: preset.id == settings.searchFilterPresets.first?.id,
                    isLast: preset.id == settings.searchFilterPresets.last?.id,
                    onMove: { move(preset.id, by: $0) },
                    onRemove: { settings.searchFilterPresets.removeAll { $0.id == preset.id } }
                )
                Divider()
            }

            settingsRow {
                HStack {
                    Button("Add Shortcut") {
                        let preset = SearchFilterPreset(name: "")
                        settings.searchFilterPresets.append(preset)
                        editingID = preset.id
                    }
                    .buttonStyle(.seeleSecondary(.small))

                    Spacer()

                    Button("Reset to Defaults") {
                        settings.searchFilterPresets = SearchFilterPreset.defaults
                    }
                    .buttonStyle(.seeleSecondary(.small))
                }
            }
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = settings.searchFilterPresets.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard settings.searchFilterPresets.indices.contains(target) else { return }
        settings.searchFilterPresets.swapAt(index, target)
    }
}

private struct SearchPresetRow: View {
    @Binding var preset: SearchFilterPreset
    @Binding var isEditing: Bool
    let isFirst: Bool
    let isLast: Bool
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        settingsRow {
            HStack(spacing: SeeleSpacing.md) {
                VStack(spacing: 0) {
                    moveButton("chevron.up", label: "Move up", offset: -1, disabled: isFirst)
                    moveButton("chevron.down", label: "Move down", offset: 1, disabled: isLast)
                }

                VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                    Text(preset.name.isEmpty ? "Untitled" : preset.name)
                        .font(SeeleTypography.body)
                        .foregroundStyle(preset.name.isEmpty ? SeeleColors.textTertiary : SeeleColors.textPrimary)
                    Text(summary)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(preset.isComplete ? SeeleColors.textTertiary : SeeleColors.warning)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)

                Spacer(minLength: SeeleSpacing.md)

                Button("Edit") {
                    isEditing = true
                }
                .buttonStyle(.seeleSecondary(.small))
                .accessibilityLabel("Edit shortcut \(preset.name)")
                .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                    SearchPresetForm(preset: $preset)
                }

                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.seeleSecondary(.small))
                    .accessibilityLabel("Remove shortcut \(preset.name)")
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if !preset.extensions.isEmpty {
            parts.append(preset.extensions.sorted().map { $0.uppercased() }.joined(separator: ", "))
        }
        if let bitrate = preset.minBitrate { parts.append("\(bitrate) kbps+") }
        if let rate = preset.minSampleRate { parts.append(SearchPresetForm.sampleRateLabel(rate)) }
        if let depth = preset.minBitDepth { parts.append("\(depth)-bit+") }
        return parts.isEmpty
            ? "Needs extensions or a minimum to appear in the search bar"
            : parts.joined(separator: " · ")
    }

    private func moveButton(_ symbol: String, label: String, offset: Int, disabled: Bool) -> some View {
        Button {
            onMove(offset)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: SeeleSpacing.iconSizeXS, weight: .semibold))
                .frame(width: SeeleSpacing.lg, height: SeeleSpacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? SeeleColors.textTertiary.opacity(0.4) : SeeleColors.textSecondary)
        .disabled(disabled)
        .accessibilityLabel("\(label) \(preset.name)")
    }
}

private struct SearchPresetForm: View {
    @Binding var preset: SearchFilterPreset

    /// Raw text is kept separately so a trailing comma or space survives
    /// typing; the parsed set is written through on every change.
    @State private var extensionsText: String

    init(preset: Binding<SearchFilterPreset>) {
        _preset = preset
        _extensionsText = State(initialValue: preset.wrappedValue.extensions.sorted().joined(separator: " "))
    }

    private static let bitrates: [(String, Int?)] = [("Any", nil), ("128 kbps+", 128), ("192 kbps+", 192), ("256 kbps+", 256), ("320 kbps+", 320)]
    private static let sampleRates: [(String, Int?)] = [("Any", nil)] + [44_100, 48_000, 96_000].map { (sampleRateLabel($0), $0) }
    private static let bitDepths: [(String, Int?)] = [("Any", nil), ("16-bit+", 16), ("24-bit+", 24), ("32-bit+", 32)]

    static func sampleRateLabel(_ hz: Int) -> String {
        hz % 1000 == 0 ? "\(hz / 1000) kHz+" : "\(Double(hz) / 1000) kHz+"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            TextField("Name", text: $preset.name)
                .textFieldStyle(SeeleTextFieldStyle())
                .accessibilityLabel("Shortcut name")

            TextField("Extensions (mp3 flac …)", text: $extensionsText)
                .textFieldStyle(SeeleTextFieldStyle())
                .font(SeeleTypography.mono)
                .accessibilityLabel("File extensions")
                .onChange(of: extensionsText) { _, text in
                    preset.extensions = SearchFilterPreset.parseExtensions(text)
                }

            Text("Separate extensions with spaces or commas.")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            Divider()

            constraintRow("Bitrate", selection: $preset.minBitrate, options: Self.bitrates)
            constraintRow("Sample rate", selection: $preset.minSampleRate, options: Self.sampleRates)
            constraintRow("Bit depth", selection: $preset.minBitDepth, options: Self.bitDepths)
        }
        .padding(SeeleSpacing.lg)
        .frame(width: 300)
    }

    private func constraintRow(_ title: String, selection: Binding<Int?>, options: [(String, Int?)]) -> some View {
        HStack {
            Text(title)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .accessibilityHidden(true)

            Spacer()

            Picker("", selection: selection) {
                ForEach(options, id: \.0) { label, value in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel("Minimum \(title.lowercased())")
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        SearchPresetsEditor(settings: SettingsState())
            .padding()
    }
    .frame(width: 520, height: 400)
    .background(SeeleColors.background)
}
#endif

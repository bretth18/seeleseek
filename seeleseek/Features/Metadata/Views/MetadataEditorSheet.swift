import SwiftUI

/// Sheet for editing file metadata with MusicBrainz integration
struct MetadataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: MetadataState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            HStack(alignment: .top, spacing: SeeleSpacing.lg) {
                // Left: Search and results
                RecordingSearchResults(state: state)
                    .frame(minWidth: 300)

                Divider()

                // Right: Editable metadata and cover art
                editableMetadataSection
                    .frame(minWidth: 280, maxWidth: 320)
            }
            .padding(SeeleSpacing.lg)

            Divider()

            // Footer
            footer
        }
        .frame(minWidth: 750, minHeight: 550)
        .background(SeeleColors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text("Edit Metadata")
                    .font(SeeleTypography.title)
                    .foregroundStyle(SeeleColors.textPrimary)

                Text(state.currentFilename)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Cancel") {
                state.closeEditor()
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(SeeleSpacing.lg)
    }

    // MARK: - Editable Metadata Section

    private var editableMetadataSection: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            Text("Metadata")
                .font(SeeleTypography.headline)
                .foregroundStyle(SeeleColors.textPrimary)

            // Cover art with edit options
            CoverArtEditView(state: state)

            // Editable metadata fields
            ScrollView {
                VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                    editableField("Title", text: $state.editTitle)
                    editableField("Artist", text: $state.editArtist)
                    editableField("Album", text: $state.editAlbum)

                    HStack(spacing: SeeleSpacing.sm) {
                        editableField("Year", text: $state.editYear)
                            .frame(width: 80)
                        editableField("Track #", text: $state.editTrackNumber)
                            .frame(width: 80)
                        Spacer()
                    }

                    editableField("Genre", text: $state.editGenre)
                }
            }

            if let error = state.applyError {
                Text(error)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.error)
            }

            Spacer()
        }
    }

    private func editableField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
            Text(label)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(SeeleTypography.body)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Show what will be applied
            if !state.editTitle.isEmpty || !state.editArtist.isEmpty {
                HStack(spacing: SeeleSpacing.xs) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(SeeleColors.textTertiary)
                    Text("Will apply: \(state.editTitle.isEmpty ? "(no title)" : state.editTitle) by \(state.editArtist.isEmpty ? "(no artist)" : state.editArtist)")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Text("Enter metadata or search MusicBrainz to get started")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Spacer()

            if state.isApplying {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, SeeleSpacing.sm)
            }

            Button("Apply Metadata") {
                Task {
                    if await state.applyMetadata() {
                        state.closeEditor()
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isApplying || (state.editTitle.isEmpty && state.editArtist.isEmpty))
        }
        .padding(SeeleSpacing.lg)
    }
}

#Preview {
    MetadataEditorSheet(state: MetadataState())
}

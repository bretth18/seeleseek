import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Cover art display with drag-and-drop, file picker, and MusicBrainz source indicator
struct CoverArtEditView: View {
    @Bindable var state: MetadataState

    var body: some View {
        VStack(spacing: SeeleSpacing.sm) {
            // Cover art display
            ZStack {
                if state.isLoadingCoverArt {
                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                        .fill(SeeleColors.surfaceSecondary)
                        .frame(width: 150, height: 150)
                        .overlay {
                            ProgressView()
                        }
                } else if let data = state.coverArtData {
                    #if os(macOS)
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 150, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                            .shadow(radius: 4)
                    }
                    #else
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 150, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                            .shadow(radius: 4)
                    }
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                        .fill(SeeleColors.surfaceSecondary)
                        .frame(width: 150, height: 150)
                        .overlay {
                            VStack(spacing: SeeleSpacing.xs) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: SeeleSpacing.iconSizeXL))
                                    .foregroundStyle(SeeleColors.textTertiary)
                                Text("Drop image here")
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                handleImageDrop(providers)
            }

            // Cover art action buttons
            HStack(spacing: SeeleSpacing.sm) {
                #if os(macOS)
                Button("Choose...") {
                    state.selectCoverArtFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif

                if state.coverArtData != nil {
                    Button("Clear") {
                        state.clearCoverArt()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(SeeleColors.error)
                }
            }

            // Source indicator
            if state.coverArtData != nil {
                Text(coverArtSourceText)
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }
        }
    }

    private var coverArtSourceText: String {
        switch state.coverArtSource {
        case .none: return ""
        case .embedded: return "From file"
        case .musicBrainz: return "From MusicBrainz"
        case .manual: return "Custom image"
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try to load as file URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        state.loadCoverArtFromFile(url)
                    }
                }
            }
            return true
        }

        // Try to load as image data
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data = data {
                    DispatchQueue.main.async {
                        state.setCoverArt(data)
                    }
                }
            }
            return true
        }

        return false
    }
}

#Preview {
    CoverArtEditView(state: MetadataState())
        .frame(width: 300)
        .padding()
        .background(SeeleColors.background)
}

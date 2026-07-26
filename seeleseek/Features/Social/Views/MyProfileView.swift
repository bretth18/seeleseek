import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import SeeleseekCore
#endif

struct MyProfileView: View {
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    @State private var editingDescription: String = ""
    @State private var hasChanges = false
    @State private var pictureError: String?

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: SeeleSpacing.lg) {
            
            // Header
            HStack {
                Text("My Profile")
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                if hasChanges {
                    Button("Save") {
                        saveProfile()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SeeleColors.accent)
                }
            }

            Text("This information is shared when other users view your profile.")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            // Profile Picture
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                Text("Profile Picture")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: SeeleSpacing.md) {
                    if let pictureData = socialState.myPicture,
                       let nsImage = NSImage(data: pictureData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                            .accessibilityLabel("Profile picture")
                    } else {
                        RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                            .fill(SeeleColors.surfaceSecondary)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Image(systemName: "person.crop.square")
                                    .font(.system(size: 32))
                                    .foregroundStyle(SeeleColors.textTertiary)
                            }
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                        Button("Choose Image...") {
                            choosePicture()
                        }

                        if socialState.myPicture != nil {
                            Button("Remove") {
                                socialState.myPicture = nil
                                hasChanges = true
                            }
                            .foregroundStyle(SeeleColors.error)
                            .accessibilityLabel("Remove profile picture")
                        }

                        Text("JPEG or PNG, max 256 KB")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)

                        if let pictureError {
                            Text(pictureError)
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.error)
                        }
                    }
                }
            }

            Divider().background(SeeleColors.surfaceSecondary)

            // Description editor
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                Text("Description")
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                TextEditor(text: $editingDescription)
                    .font(SeeleTypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(SeeleSpacing.sm)
                    .frame(height: 120)
                    .background(SeeleColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                    .onChange(of: editingDescription) { _, newValue in
                        hasChanges = newValue != socialState.myDescription
                    }
                    .accessibilityLabel("Profile description")

                Text("\(editingDescription.count) / 1000 characters")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Divider().background(SeeleColors.surfaceSecondary)

            // Privileges
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                HStack {
                    Text("Privileges")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Button("Check Status") {
                        socialState.checkPrivileges()
                    }
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.accent)
                    .accessibilityLabel("Check privilege status")
                }

                HStack(spacing: SeeleSpacing.sm) {
                    Image(systemName: socialState.privilegeTimeRemaining > 0 ? "star.fill" : "star")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(socialState.privilegeTimeRemaining > 0 ? SeeleColors.warning : SeeleColors.textTertiary)
                        .accessibilityHidden(true)

                    Text(socialState.formattedPrivilegeTime)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)

                    Spacer()

                    Link(destination: URL(string: "https://www.slsknet.org/donate")!) {
                        Label("Get Privileges", systemImage: "arrow.up.right.square")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)
                    }
                    
                }
            }

            Divider().background(SeeleColors.surfaceSecondary)

            // My Interests Summary
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                HStack {
                    Text("My Interests")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Button("Edit") {
                        appState.sidebarSelection = .social
                    }
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.accent)
                    .accessibilityLabel("Edit interests")
                }

                if socialState.myLikes.isEmpty && socialState.myHates.isEmpty {
                    Text("No interests added yet. Add some to help others find you.")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                        if !socialState.myLikes.isEmpty {
                            // Only the heart icon shows the difference
                            // between likes and dislikes. Thus the
                            // combined label speaks it.
                            HStack(spacing: SeeleSpacing.xs) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: SeeleSpacing.iconSizeXS))
                                    .foregroundStyle(SeeleColors.success)
                                Text(socialState.myLikes.prefix(5).joined(separator: ", "))
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textSecondary)
                                if socialState.myLikes.count > 5 {
                                    Text("+\(socialState.myLikes.count - 5) more")
                                        .font(SeeleTypography.caption)
                                        .foregroundStyle(SeeleColors.textTertiary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(likesSummaryLabel)
                        }

                        if !socialState.myHates.isEmpty {
                            HStack(spacing: SeeleSpacing.xs) {
                                Image(systemName: "heart.slash.fill")
                                    .font(.system(size: SeeleSpacing.iconSizeXS))
                                    .foregroundStyle(SeeleColors.error)
                                Text(socialState.myHates.prefix(5).joined(separator: ", "))
                                    .font(SeeleTypography.caption)
                                    .foregroundStyle(SeeleColors.textSecondary)
                                if socialState.myHates.count > 5 {
                                    Text("+\(socialState.myHates.count - 5) more")
                                        .font(SeeleTypography.caption)
                                        .foregroundStyle(SeeleColors.textTertiary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(dislikesSummaryLabel)
                        }
                    }
                }
            }
        }
        .padding(SeeleSpacing.lg)
        .background(SeeleColors.surface, in: RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .onAppear {
            editingDescription = socialState.myDescription
            socialState.checkPrivileges()
        }
    }

    private var likesSummaryLabel: String {
        var label = "Likes: " + socialState.myLikes.prefix(5).joined(separator: ", ")
        if socialState.myLikes.count > 5 {
            label += ", plus \(socialState.myLikes.count - 5) more"
        }
        return label
    }

    private var dislikesSummaryLabel: String {
        var label = "Dislikes: " + socialState.myHates.prefix(5).joined(separator: ", ")
        if socialState.myHates.count > 5 {
            label += ", plus \(socialState.myHates.count - 5) more"
        }
        return label
    }

    private func saveProfile() {
        socialState.myDescription = editingDescription
        Task {
            await socialState.saveMyProfile()
            hasChanges = false
        }
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a profile picture (max 256 KB)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        pictureError = nil

        do {
            var data = try Data(contentsOf: url)

            // Resize if too large (SoulSeek protocol limit is typically ~256KB for pictures)
            let maxSize = 256 * 1024
            if data.count > maxSize {
                // Try to compress as JPEG
                if let nsImage = NSImage(data: data),
                   let tiffData = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    // Try progressively lower quality until under size limit
                    for quality in stride(from: 0.8, through: 0.1, by: -0.1) {
                        if let compressed = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]),
                           compressed.count <= maxSize {
                            data = compressed
                            break
                        }
                    }
                }

                if data.count > maxSize {
                    // Still too large after compression. A silent
                    // return leaves a VoiceOver user with no feedback.
                    pictureError = "Image is too large"
                    VoiceOverAnnouncer.shared.announce("Image is too large")
                    return
                }
            }

            socialState.myPicture = data
            hasChanges = true
        } catch {
            pictureError = "Can not read the image file"
            VoiceOverAnnouncer.shared.announce("Can not read the image file")
        }
    }
}

#Preview {
    MyProfileView()
        .environment(\.appState, {
            let state = AppState()
            state.socialState.myDescription = "Music lover sharing my collection."
            state.socialState.myLikes = ["jazz", "electronic", "ambient", "classical", "experimental", "vinyl"]
            state.socialState.myHates = ["pop", "country"]
            return state
        }())
        .frame(width: 400)
        .padding()
}

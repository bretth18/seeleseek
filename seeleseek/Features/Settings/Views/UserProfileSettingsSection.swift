import SwiftUI
import UniformTypeIdentifiers
import SeeleseekCore
#if os(macOS)
import AppKit
#endif

struct UserProfileSettingsSection: View {
    @Environment(\.appState) private var appState

    private var socialState: SocialState {
        appState.socialState
    }

    private static let descriptionLimit = 1000

    @State private var editingDescription: String = ""
    @State private var pictureError: String?
    @FocusState private var descriptionFocused: Bool

    private var isPrivileged: Bool {
        socialState.privilegeTimeRemaining > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.md) {
            settingsHeader("Profile")

            settingsGroup(nil) {
                settingsRow {
                    identityRow
                        .padding(.vertical, SeeleSpacing.sm)
                }

                if let pictureError {
                    settingsCaption {
                        Text(pictureError)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.error)
                    }
                } else {
                    settingsCaption("JPEG or PNG, up to 256 KB.")
                }
            }

            settingsGroup("About") {
                settingsRow {
                    descriptionEditor
                        .padding(.vertical, SeeleSpacing.xs)
                }

                settingsCaption {
                    HStack {
                        Text("Shown to anyone who views your profile.")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)

                        Spacer()

                        Text(verbatim: "\(editingDescription.count) / \(Self.descriptionLimit)")
                            .font(SeeleTypography.mono)
                            .foregroundStyle(editingDescription.count > Self.descriptionLimit ? SeeleColors.error : SeeleColors.textTertiary)
                            .accessibilityLabel("\(editingDescription.count) of \(Self.descriptionLimit) characters")
                    }
                }
            }

            settingsGroup("Interests") {
                settingsRow {
                    interestsContent
                        .padding(.vertical, SeeleSpacing.xs)
                }

                settingsRow {
                    HStack {
                        Text("Add or remove interests under Social › Interests.")
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textTertiary)

                        Spacer()

                        Button("Edit Interests…") {
                            appState.navigation.navigate(to: .social(.interests))
                        }
                        .buttonStyle(.seeleSecondary(.small))
                        .accessibilityLabel("Edit interests in the Social tab")
                    }
                }
            }

            settingsGroup("Privileges") {
                settingsRow {
                    privilegesRow
                        .padding(.vertical, SeeleSpacing.xs)
                }

                settingsCaption {
                    Link("Get privileges on slsknet.org", destination: URL(string: "https://www.slsknet.org/donate")!)
                        .buttonStyle(.plain)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.accent)
                }
            }
        }
        .onAppear {
            editingDescription = socialState.myDescription
            socialState.checkPrivileges()
        }
        .onDisappear {
            saveDescriptionIfChanged()
        }
        .onChange(of: descriptionFocused) { _, focused in
            if !focused { saveDescriptionIfChanged() }
        }
    }

    // MARK: - Identity

    private var identityRow: some View {
        HStack(spacing: SeeleSpacing.lg) {
            avatar

            VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
                HStack(spacing: SeeleSpacing.sm) {
                    Text(displayUsername)
                        .font(SeeleTypography.title2)
                        .foregroundStyle(SeeleColors.textPrimary)

                    if isPrivileged {
                        Image(systemName: "star.fill")
                            .font(.system(size: SeeleSpacing.iconSizeSmall))
                            .foregroundStyle(SeeleColors.warning)
                            .accessibilityLabel("Privileged user")
                    }
                }

                HStack(spacing: SeeleSpacing.xs) {
                    StandardStatusDot(isOnline: isLoggedIn)
                        .accessibilityHidden(true)
                    Text(isLoggedIn ? "Online" : "Offline")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textSecondary)
                }

                HStack(spacing: SeeleSpacing.sm) {
                    Button("Choose Picture…") {
                        choosePicture()
                    }
                    .buttonStyle(.seeleSecondary(.small))

                    if socialState.myPicture != nil {
                        Button("Remove", role: .destructive) {
                            socialState.myPicture = nil
                            pictureError = nil
                            saveProfile()
                        }
                        .buttonStyle(.seeleSecondary(.small))
                        .accessibilityLabel("Remove profile picture")
                    }
                }
                .padding(.top, SeeleSpacing.xs)
            }

            Spacer()
        }
    }

    private var displayUsername: String {
        let name = appState.networkClient.status.username
        return name.isEmpty ? "Not signed in" : name
    }

    private var isLoggedIn: Bool {
        appState.networkClient.status.loggedIn
    }

    private static let avatarSize: CGFloat = 64

    @ViewBuilder
    private var avatar: some View {
        if let pictureData = socialState.myPicture,
           let nsImage = NSImage(data: pictureData) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .clipShape(Circle())
                .accessibilityLabel("Profile picture")
        } else {
            Circle()
                .fill(SeeleColors.surfaceSecondary)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: SeeleSpacing.iconSizeLarge))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .accessibilityHidden(true)
        }
    }

    // MARK: - Description

    private var descriptionEditor: some View {
        TextEditor(text: $editingDescription)
            .font(SeeleTypography.body)
            .foregroundStyle(SeeleColors.textPrimary)
            .scrollContentBackground(.hidden)
            .focused($descriptionFocused)
            .padding(.horizontal, SeeleSpacing.sm)
            .padding(.vertical, SeeleSpacing.sm)
            .frame(minHeight: 96)
            .background(SeeleColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(SeeleColors.border, lineWidth: SeeleSpacing.strokeThin)
            )
            .overlay(alignment: .topLeading) {
                if editingDescription.isEmpty {
                    Text("Tell other users about yourself and what you share.")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textTertiary)
                        .padding(.horizontal, SeeleSpacing.sm + SeeleSpacing.xs)
                        .padding(.vertical, SeeleSpacing.sm)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Profile description")
    }

    private func saveDescriptionIfChanged() {
        guard editingDescription != socialState.myDescription else { return }
        saveProfile()
    }

    // MARK: - Interests

    @ViewBuilder
    private var interestsContent: some View {
        if socialState.myLikes.isEmpty && socialState.myHates.isEmpty {
            Text("No interests yet. Interests help other users with similar taste find you.")
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
                if !socialState.myLikes.isEmpty {
                    interestsLine("Likes", items: socialState.myLikes, color: SeeleColors.success)
                }
                if !socialState.myHates.isEmpty {
                    interestsLine("Dislikes", items: socialState.myHates, color: SeeleColors.error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func interestsLine(_ title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.xs) {
            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)

            FlowLayout(spacing: SeeleSpacing.xs) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(color)
                        .padding(.horizontal, SeeleSpacing.sm)
                        .padding(.vertical, SeeleSpacing.xs)
                        .background(color.opacity(SeeleColors.alphaMedium), in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(items.joined(separator: ", "))")
    }

    // MARK: - Privileges

    private var privilegesRow: some View {
        HStack(spacing: SeeleSpacing.md) {
            Circle()
                .fill((isPrivileged ? SeeleColors.warning : SeeleColors.textTertiary).opacity(SeeleColors.alphaMedium))
                .frame(width: SeeleSpacing.iconSizeXL, height: SeeleSpacing.iconSizeXL)
                .overlay {
                    Image(systemName: isPrivileged ? "star.fill" : "star")
                        .font(.system(size: SeeleSpacing.iconSize))
                        .foregroundStyle(isPrivileged ? SeeleColors.warning : SeeleColors.textTertiary)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SeeleSpacing.xxs) {
                Text(socialState.formattedPrivilegeTime)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)

                Text(isPrivileged
                     ? "Your downloads move ahead in other users' upload queues."
                     : "Privileged users move ahead in other users' upload queues.")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Refresh") {
                socialState.checkPrivileges()
            }
            .buttonStyle(.seeleSecondary(.small))
            .accessibilityLabel("Refresh privilege status")
        }
    }

    // MARK: - Saving

    private func saveProfile() {
        socialState.myDescription = editingDescription
        Task {
            await socialState.saveMyProfile()
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
            saveProfile()
        } catch {
            pictureError = "Can not read the image file"
            VoiceOverAnnouncer.shared.announce("Can not read the image file")
        }
    }
}

#Preview {
    ScrollView {
        UserProfileSettingsSection()
            .environment(\.appState, {
                let state = AppState()
                state.socialState.myDescription = "Music lover sharing my collection."
                state.socialState.myLikes = ["jazz", "electronic", "ambient", "classical", "experimental", "vinyl"]
                state.socialState.myHates = ["pop", "country"]
                return state
            }())
            .padding()
    }
    .frame(width: 520, height: 720)
    .background(SeeleColors.background)
}

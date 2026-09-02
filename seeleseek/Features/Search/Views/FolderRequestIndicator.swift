import SwiftUI

/// Folder-contents request state, sized for a list row's action cluster.
struct FolderRequestIndicator: View {
    let state: AppState.FolderRequestState
    let username: String

    var body: some View {
        switch state {
        case .fetching:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(SeeleSpacing.scaleSmall)
                .frame(width: SeeleSpacing.buttonHeight, height: SeeleSpacing.buttonHeight)
                .rowHelp("Getting folder contents from \(username)...")
                .accessibilityLabel("Getting folder contents from \(username)")
        case .failed(let reason):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: SeeleSpacing.iconSizeSmall))
                .foregroundStyle(SeeleColors.warning)
                .frame(width: SeeleSpacing.buttonHeight, height: SeeleSpacing.buttonHeight)
                .rowHelp(reason)
                .accessibilityLabel("Folder download failed. \(reason)")
        }
    }
}

#if DEBUG
#Preview("Folder request indicator") {
    HStack(spacing: SeeleSpacing.lg) {
        FolderRequestIndicator(state: .fetching, username: "vinylcollector")
        FolderRequestIndicator(
            state: .failed("Could not reach jazzfan after 32 seconds"),
            username: "jazzfan"
        )
    }
    .padding(SeeleSpacing.lg)
    .background(SeeleColors.background)
    .preferredColorScheme(.dark)
}
#endif

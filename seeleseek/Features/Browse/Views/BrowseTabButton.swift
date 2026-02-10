import SwiftUI

struct BrowseTabButton: View {
    let browse: UserShares
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            if browse.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: SeeleSpacing.iconSizeSmall - 2, height: SeeleSpacing.iconSizeSmall - 2)
            } else if browse.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                    .foregroundStyle(SeeleColors.error)
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
                    .foregroundStyle(SeeleColors.warning)
            }

            Text(browse.username)
                .font(SeeleTypography.caption)
                .foregroundStyle(isSelected ? SeeleColors.textPrimary : SeeleColors.textSecondary)
                .lineLimit(1)

            if !browse.isLoading && browse.error == nil && !browse.folders.isEmpty {
                Text("\(browse.totalFiles)")
                    .font(SeeleTypography.monoSmall)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: SeeleSpacing.iconSizeXS - 2, weight: .bold))
                    .foregroundStyle(SeeleColors.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
        .background(isSelected ? SeeleColors.surface : SeeleColors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                .stroke(isSelected ? SeeleColors.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

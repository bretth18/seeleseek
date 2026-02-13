import SwiftUI

/// Consistent search field component
struct StandardSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var isLoading: Bool = false
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
                    .frame(width: SeeleSpacing.iconSizeSmall, height: SeeleSpacing.iconSizeSmall)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SeeleSpacing.md)
        .padding(.vertical, SeeleSpacing.sm)
        .background(SeeleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
    }
}

#Preview {
    VStack(spacing: SeeleSpacing.md) {
        StandardSearchField(text: .constant(""), placeholder: "Search files...")
        StandardSearchField(text: .constant("Beatles"), placeholder: "Search files...")
    }
    .padding()
    .background(SeeleColors.background)
}

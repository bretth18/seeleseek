import SwiftUI
import SeeleseekCore

/// Consistent search field component
struct StandardSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var icon: String = "magnifyingglass"
    var isLoading: Bool = false
    /// Spoken name for the built-in clear button. Override when the field
    /// holds something other than a search query ("Clear username").
    var clearLabel: String = "Clear search text"
    var onSubmit: (() -> Void)?
    /// Runs after the built-in clear button empties the text, for hosts
    /// that must reset more than the query string.
    var onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
                    .frame(width: SeeleSpacing.iconSizeSmall, height: SeeleSpacing.iconSizeSmall)
                    .accessibilityLabel("Searching")
            } else {
                Image(systemName: icon)
                    .font(.system(size: SeeleSpacing.iconSizeSmall))
                    .foregroundStyle(SeeleColors.textTertiary)
                    .accessibilityHidden(true)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(SeeleTypography.body)
                .foregroundStyle(SeeleColors.textPrimary)
                .onSubmit {
                    onSubmit?()
                }
                // A placeholder is not a label. Without a label,
                // VoiceOver reads the field as unnamed after the user
                // types text.
                .accessibilityLabel(placeholder.trimmingCharacters(in: CharacterSet(charactersIn: ".… ")))

            if !text.isEmpty {
                Button {
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeSmall))
                        .foregroundStyle(SeeleColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, SeeleSpacing.md)
        .frame(minHeight: SeeleSpacing.controlHeight)
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

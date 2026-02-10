import SwiftUI

/// Capsule badge showing an unread message count
struct UnreadCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textOnAccent)
                .padding(.horizontal, SeeleSpacing.rowVertical)
                .padding(.vertical, SeeleSpacing.xxs)
                .background(SeeleColors.accent)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    HStack(spacing: SeeleSpacing.md) {
        UnreadCountBadge(count: 3)
        UnreadCountBadge(count: 42)
        UnreadCountBadge(count: 0)
    }
    .padding()
    .background(SeeleColors.background)
}

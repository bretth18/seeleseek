import SwiftUI

/// Consistent section header for lists and content areas
struct StandardSectionHeader: View {
    let title: String
    var count: Int?
    var trailing: AnyView?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
        self.trailing = nil
    }

    init<Trailing: View>(_ title: String, count: Int? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.count = count
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: SeeleSpacing.sm) {
            Text(title)
                .font(SeeleTypography.caption)
                .foregroundStyle(SeeleColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            if let count {
                Text("(\(count))")
                    .font(SeeleTypography.caption)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, SeeleSpacing.lg)
        .padding(.vertical, SeeleSpacing.sm)
    }
}

#Preview {
    VStack {
        StandardSectionHeader("Downloads", count: 42)
        StandardSectionHeader("Uploads") {
            Button("Clear") {}
                .font(SeeleTypography.caption)
        }
    }
    .background(SeeleColors.background)
}

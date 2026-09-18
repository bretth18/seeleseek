import SwiftUI

struct SearchSortMenu: View {
    let searchState: SearchState

    var body: some View {
        Menu {
            ForEach(SearchState.SortOrder.allCases, id: \.self) { order in
                Button {
                    searchState.sortOrder = order
                } label: {
                    HStack {
                        Text(order.rawValue)
                        if searchState.sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: SeeleSpacing.xs) {
                Text("Sort: \(searchState.sortOrder.rawValue)")
                    .font(SeeleTypography.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: SeeleSpacing.iconSizeXS))
            }
            .foregroundStyle(SeeleColors.textSecondary)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

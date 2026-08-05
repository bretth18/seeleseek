import SwiftUI

/// The 32pt leading badge every list row opens with: a `badgeShape` filled
/// with the caller's tint at `alphaMedium`, holding a same-tint glyph.
///
/// This shape was hand-rolled independently in `RowDirectionGlyph`,
/// `SearchResultRow.fileGlyph` and the grouped-folder header. One definition
/// keeps the leading column identical across search, transfers, history and
/// grouped results — which is the whole reason rows line up.
struct RowGlyph: View {
    let systemName: String
    let tint: Color
    var glyphSize: CGFloat = SeeleSpacing.iconSize
    var weight: Font.Weight = .medium

    static let size: CGFloat = SeeleSpacing.iconSizeXL

    var body: some View {
        ZStack {
            RoundedRectangle.badgeShape
                .fill(tint.opacity(SeeleColors.alphaMedium))
                .frame(width: Self.size, height: Self.size)

            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: weight))
                .foregroundStyle(tint)
        }
    }
}

/// Corner ornament for a `RowGlyph` — the private-file lock on a search
/// result, the expansion chevron on a folder header. Kept here so the offset
/// and backing circle stay identical wherever one is used.
struct RowGlyphOrnament: View {
    let systemName: String
    var tint: Color = SeeleColors.textPrimary
    var rotation: Angle = .zero

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: SeeleSpacing.iconSizeXXS, weight: .bold))
            .foregroundStyle(tint)
            .padding(SeeleSpacing.xxs)
            .background(SeeleColors.surface, in: Circle())
            .rotationEffect(rotation)
            .offset(x: SeeleSpacing.xxs, y: SeeleSpacing.xxs)
    }
}

#Preview {
    HStack(spacing: SeeleSpacing.lg) {
        RowGlyph(systemName: "waveform", tint: SeeleColors.success)
        RowGlyph(systemName: "folder.fill", tint: SeeleColors.warning)
            .overlay(alignment: .bottomTrailing) {
                RowGlyphOrnament(systemName: "chevron.right", rotation: .degrees(90))
            }
        RowGlyph(systemName: "arrow.down", tint: SeeleColors.info, weight: .bold)
    }
    .padding()
    .background(SeeleColors.background)
}

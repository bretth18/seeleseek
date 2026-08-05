import SwiftUI

/// The badge chrome every list row's leading column is built from: a
/// `badgeShape` filled with the caller's tint at `alphaMedium`. Size is
/// pinned by `RowGlyphTests`.
///
/// Split from `RowGlyph` so callers whose content is not a symbol — the
/// connecting spinner in `RowDirectionGlyph` — compose with it instead of
/// hand-rolling the fill and frame again. This is the single definition of
/// the leading column's size and fill, which is what makes rows line up.
struct RowGlyphBadge<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    static var size: CGFloat { SeeleSpacing.iconSizeXL }

    var body: some View {
        ZStack {
            RoundedRectangle.badgeShape
                .fill(tint.opacity(SeeleColors.alphaMedium))
                .frame(width: Self.size, height: Self.size)

            content
        }
    }
}

/// The common case: one SF Symbol in the badge's tint.
struct RowGlyph: View {
    let systemName: String
    let tint: Color
    var glyphSize: CGFloat = SeeleSpacing.iconSize
    var weight: Font.Weight = .medium

    static var size: CGFloat { RowGlyphBadge<EmptyView>.size }

    var body: some View {
        RowGlyphBadge(tint: tint) {
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: weight))
                .foregroundStyle(tint)
        }
    }
}

/// Corner ornament for a row glyph — the private-file lock on a search
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
        RowGlyphBadge(tint: SeeleColors.info) {
            ProgressView().progressViewStyle(.circular).scaleEffect(SeeleSpacing.scaleSmall)
        }
    }
    .padding()
    .background(SeeleColors.background)
}

import SwiftUI

// Glass over the lock screen.
//
// Liquid Glass and blur materials refract what is behind them. In the SkyLight space above the
// lock screen they can't see anything behind the window and come out flat, and the lock screen
// wallpaper can't be read (dynamic wallpapers such as Macintosh aren't files and keep moving).
// So glass cards there become translucent panels with glass edges that let the real lock screen
// show through.

private struct LockOriginKey: EnvironmentKey {
    static let defaultValue: CGPoint? = nil
}

extension EnvironmentValues {
    /// Top-left corner, in screen points, of a card drawn over the lock screen; nil elsewhere.
    var lockOrigin: CGPoint? {
        get { self[LockOriginKey.self] }
        set { self[LockOriginKey.self] = newValue }
    }
}

/// A translucent tinted panel with glass edges, letting the lock screen show through.
struct LockScreenPanel: ViewModifier {
    let style: CardStyle
    let accent: Color
    let tint: Color?
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        content
            .background { fill }
            .clipShape(shape)
            // Glass reads from its edges: a bright rim catching light at the top left,
            // a thinner one at the bottom right, and a soft dark line just inside.
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08), .white.opacity(0.06), .white.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5))
            .overlay(
                shape.inset(by: 1.5)
                    .stroke(.black.opacity(0.12), lineWidth: 1)
                    .blur(radius: 1.5)
                    .clipShape(shape))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }

    /// Clear glass barely tints what is behind it, so the moving lock screen wallpaper shows
    /// through; frosted styles can't blur here, so they get more body to keep text legible.
    @ViewBuilder
    private var fill: some View {
        ZStack {
            switch style {
            case .clearGlass: Color.black.opacity(0.1)
            case .tinted: accent.opacity(0.45); Color.black.opacity(0.12)
            default: Color.black.opacity(0.42)
            }
            if let tint { tint.opacity(style == .clearGlass ? 0.35 : 0.55) }
            // Sheen: light pooling at the top of the glass.
            LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03), .clear],
                           startPoint: .top, endPoint: .center)
        }
    }
}

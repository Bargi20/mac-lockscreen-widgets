import SwiftUI

/// Glass over the lock screen.
///
/// Liquid Glass and blur materials sample what is behind the window, and over the lock screen
/// macOS doesn't let an app see what is behind it: the cards would come out empty. The image
/// the lock screen shows can't be known reliably either (it isn't always the desktop picture
/// macOS reports), so glass cards there become translucent tinted panels with a light edge,
/// which let the real lock screen show through.
private struct LockScreenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True for cards drawn over the lock screen, where real glass can't be drawn.
    var onLockScreen: Bool {
        get { self[LockScreenKey.self] }
        set { self[LockScreenKey.self] = newValue }
    }
}

struct LockScreenGlass: ViewModifier {
    let style: CardStyle
    let accent: Color
    let tint: Color?
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        content
            .background { fill }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06), .white.opacity(0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }

    /// Without blur the background stays sharp, so the panel needs enough body to keep text legible.
    @ViewBuilder
    private var fill: some View {
        ZStack {
            switch style {
            case .clearGlass: Color.black.opacity(0.32)
            case .tinted: accent.opacity(0.5); Color.black.opacity(0.15)
            default: Color.black.opacity(0.48)
            }
            if let tint { tint.opacity(0.55) }
            LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

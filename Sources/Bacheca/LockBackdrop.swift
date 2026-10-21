import AppKit
import CoreImage
import ImageIO
import SwiftUI

/// Glass over the lock screen.
///
/// Liquid Glass and blur materials sample what is behind the window, and over the lock screen
/// macOS doesn't let an app see what is behind it: the cards would come out empty. The lock
/// screen shows the desktop wallpaper, so at lock time the wallpaper is blurred once and each
/// card shows the part of it that lies under the card.
struct LockBackdrop {
    /// Heavily blurred, for Glass and Tinted glass.
    let frosted: NSImage
    /// Lightly blurred, for Clear glass.
    let clear: NSImage
    let screen: CGSize

    @MainActor
    static func make(for screen: NSScreen) -> LockBackdrop? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let size = screen.frame.size
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(size.width, size.height)),
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

        // Fill the screen the way the lock screen does: scale to cover, then crop the middle.
        let image = CIImage(cgImage: cg)
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let crop = CGRect(x: (scaled.extent.width - size.width) / 2, y: (scaled.extent.height - size.height) / 2,
                          width: size.width, height: size.height)
        let context = CIContext()

        func blurred(radius: Double, saturation: Double) -> NSImage? {
            let output = scaled.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
                .cropped(to: crop)
            guard let result = context.createCGImage(output, from: crop) else { return nil }
            return NSImage(cgImage: result, size: size)
        }

        guard let frosted = blurred(radius: 28, saturation: 1.6),
              let clear = blurred(radius: 9, saturation: 1.3) else { return nil }
        return LockBackdrop(frosted: frosted, clear: clear, screen: size)
    }
}

/// A card's place over the lock screen backdrop.
struct LockBackdropPlacement {
    let backdrop: LockBackdrop
    /// Top-left corner of the card, in screen points.
    let origin: CGPoint
}

private struct LockBackdropKey: EnvironmentKey {
    static let defaultValue: LockBackdropPlacement? = nil
}

extension EnvironmentValues {
    /// Set only for cards on the lock screen, where real glass can't be drawn.
    var lockBackdrop: LockBackdropPlacement? {
        get { self[LockBackdropKey.self] }
        set { self[LockBackdropKey.self] = newValue }
    }
}

/// Glass drawn from the blurred wallpaper: the piece under the card, a tint, and a light edge.
struct WallpaperGlass: ViewModifier {
    let placement: LockBackdropPlacement
    let style: CardStyle
    let accent: Color
    let tint: Color?
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        let b = placement.backdrop
        // The first background sits right behind the content: tint over the blurred wallpaper.
        content
            .background { wash }
            .background(alignment: .topLeading) {
                Image(nsImage: style == .clearGlass ? b.clear : b.frosted)
                    .resizable()
                    .frame(width: b.screen.width, height: b.screen.height)
                    .offset(x: -placement.origin.x, y: -placement.origin.y)
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }

    /// Frosted glass lightens what is behind it; clear glass only dims it a little for legibility.
    @ViewBuilder
    private var wash: some View {
        ZStack {
            switch style {
            case .clearGlass: Color.black.opacity(0.18)
            case .tinted: accent.opacity(0.45)
            default: Color.white.opacity(0.12)
            }
            if let tint { tint.opacity(0.5) }
            LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

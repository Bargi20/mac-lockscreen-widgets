import AppKit
import ScreenCaptureKit
import SwiftUI

// Glass over the lock screen.
//
// Liquid Glass and blur materials refract what is behind them. In the SkyLight space above the
// lock screen they can't see anything behind the window and come out flat. Two ways around it:
// - by default, glass cards there become translucent tinted panels with a light edge;
// - with the Screen Recording permission (an option in Settings), Bacheca keeps a capture of the
//   wallpaper, draws the piece under each card inside the card, and puts real glass over it.

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

// MARK: - Wallpaper capture

/// Captures only the wallpaper window (no app windows), while the Mac is unlocked.
@MainActor
final class WallpaperCapture: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var hasPermission = CGPreflightScreenCaptureAccess()
    private var capturing = false

    init() {
        // Development aid: `--wallpaper-file <path>` uses a saved picture instead of a live capture.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--wallpaper-file"), i + 1 < args.count, let screen = NSScreen.screens.first,
           let file = NSImage(contentsOfFile: args[i + 1]) {
            file.size = screen.frame.size
            image = file
        }
    }

    /// Shows the system prompt the first time; later macOS only points to System Settings.
    func requestPermission() {
        hasPermission = CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess()
    }

    func refresh() {
        hasPermission = CGPreflightScreenCaptureAccess()
        guard hasPermission, !capturing, !isScreenLocked(), let screen = NSScreen.screens.first else { return }
        capturing = true
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        Task {
            defer { capturing = false }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let window = content.windows.first(where: {
                      $0.owningApplication?.bundleIdentifier == "com.apple.WindowManager"
                          && $0.frame.size == size && ($0.title == "Wallpaper" || $0.windowLayer < 0)
                  }) else { return }
            let config = SCStreamConfiguration()
            config.width = Int(size.width * scale)
            config.height = Int(size.height * scale)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                image = NSImage(cgImage: cg, size: size)
            }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Card backgrounds on the lock screen

/// Real glass over the captured wallpaper: the piece under the card sits inside the card,
/// so the glass has something to refract.
struct CapturedGlass: ViewModifier {
    let wallpaper: NSImage
    let origin: CGPoint
    let screen: CGSize
    let style: CardStyle
    let accent: Color
    let tint: Color?
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(style == .clearGlass ? Color.black.opacity(0.18) : Color.clear, in: shape)
                .glassEffect(glass, in: shape)
                .background(alignment: .topLeading) { piece }
                .clipShape(shape)
        } else {
            content
                .background(style == .tinted ? accent.opacity(0.5) : Color.black.opacity(0.15), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .background(alignment: .topLeading) { piece }
                .clipShape(shape)
        }
    }

    private var piece: some View {
        Image(nsImage: wallpaper)
            .resizable()
            .frame(width: screen.width, height: screen.height)
            .offset(x: -origin.x, y: -origin.y)
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let base: Glass = style == .clearGlass ? .clear : .regular
        if let color = style == .tinted ? accent : tint { return base.tint(color.opacity(0.6)) }
        return base
    }
}

/// Without a capture: a translucent tinted panel with a light edge, letting the lock screen show through.
struct LockScreenPanel: ViewModifier {
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

import AppKit
import SwiftUI

/// Transparent full-screen window. The lock-screen variant never takes focus or clicks,
/// so it cannot get between the user and the password field.
final class OverlayWindow: NSWindow {
    private let interactive: Bool
    var onEscape: () -> Void = {}

    init(screen: NSScreen, interactive: Bool) {
        self.interactive = interactive
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = !interactive
        canBecomeVisibleWithoutLogin = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // The studio sits above the menu bar but below drag images, so drag and drop stays visible.
        level = interactive ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2) : NSWindow.Level(rawValue: Int(Int32.max - 2))
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { interactive }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let env = AppEnvironment()
    private var statusItem: NSStatusItem!
    private var lockWindows: [OverlayWindow] = []
    private var previewWindow: OverlayWindow?
    private var settingsWindow: NSWindow?
    private var lockWatchdog: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        env.start()
        setUpStatusItem()

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked() }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideLockWidgets() }
        }

        if CommandLine.arguments.contains("--preview") {
            showPreview()
        } else if env.store.isFirstLaunch {
            openSettings()
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lock.rectangle.stack", accessibilityDescription: "Bacheca")
        let menu = NSMenu()
        menu.addItem(withTitle: tr("Disponi i widget…", "Arrange Widgets…"), action: #selector(showPreview), keyEquivalent: "p").target = self
        menu.addItem(withTitle: tr("Impostazioni…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Esci da Bacheca", "Quit Bacheca"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: Lock screen

    private func screenLocked() {
        hidePreview()
        env.refreshAll()
        showLockWidgets()
    }

    private func showLockWidgets() {
        hideLockWidgets()
        guard let screen = NSScreen.screens.first else { return }
        let window = OverlayWindow(screen: screen, interactive: false)
        window.contentView = NSHostingView(rootView: env.inject(LockScreenView(mode: .lock)))
        SkyLight.shared?.adopt(window)
        window.orderFrontRegardless()
        lockWindows = [window]

        // If the unlock notification is ever missed, don't leave widgets over the desktop.
        lockWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if !isScreenLocked() { self?.hideLockWidgets() }
            }
        }
    }

    private func hideLockWidgets() {
        lockWatchdog?.invalidate()
        lockWatchdog = nil
        lockWindows.forEach { $0.orderOut(nil); $0.close() }
        lockWindows = []
    }

    // MARK: Preview

    @objc func showPreview() {
        hidePreview()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = OverlayWindow(screen: screen, interactive: true)
        window.onEscape = { [weak self] in self?.hidePreview() }
        window.contentView = NSHostingView(rootView: env.inject(LockScreenView(mode: .preview) { [weak self] in self?.hidePreview() }))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
    }

    private func hidePreview() {
        previewWindow?.orderOut(nil)
        previewWindow?.close()
        previewWindow = nil
    }

    // MARK: Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Bacheca"
            window.isReleasedWhenClosed = false
            let settings = SettingsView(onPreview: { [weak self] in self?.showPreview() })
            window.contentView = NSHostingView(rootView: env.inject(settings))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

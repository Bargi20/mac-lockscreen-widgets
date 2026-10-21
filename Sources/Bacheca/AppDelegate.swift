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
        // Above the menu bar but below drag images (so drag and drop stays visible in the studio)
        // and below overlays such as a Face ID style prompt at mainMenu + 4. On the lock screen,
        // SkyLight lifts the window above the lock screen itself.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
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
    /// Keeps App Nap from slowing the widgets' timers while the screen is locked.
    private var lockActivity: NSObjectProtocol?

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

        if CommandLine.arguments.contains("--lock-preview") {
            showLockWidgets(simulated: true)
        } else if CommandLine.arguments.contains("--preview") {
            showPreview()
        } else if env.store.isFirstLaunch || CommandLine.arguments.contains("--settings") {
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

    /// `simulated` shows the lock screen layout over the desktop for a few seconds (`--lock-preview`).
    private func showLockWidgets(simulated: Bool = false) {
        hideLockWidgets()
        lockActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Showing widgets on the lock screen")
        guard let screen = NSScreen.screens.first else { return }
        let window = OverlayWindow(screen: screen, interactive: false)
        window.contentView = NSHostingView(rootView: env.inject(LockScreenView(mode: .lock)))
        if !simulated { SkyLight.shared?.adopt(window) }
        window.orderFrontRegardless()
        lockWindows = [window]
        if simulated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                MainActor.assumeIsolated { self?.hideLockWidgets() }
            }
            return
        }

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
        if let lockActivity { ProcessInfo.processInfo.endActivity(lockActivity) }
        lockActivity = nil
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
            // A standard Mac Settings window: one toolbar tab per pane, titled after the selected pane.
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            let panes: [(AnyView, String, String)] = [
                (AnyView(GeneralSettings(onArrange: { [weak self] in self?.showPreview() })), tr("Generale", "General"), "gearshape"),
                (AnyView(WidgetsSettings()), tr("Widget", "Widgets"), "square.grid.2x2"),
                (AnyView(AppearanceSettings()), tr("Aspetto", "Appearance"), "paintbrush"),
            ]
            for (view, label, symbol) in panes {
                let controller = NSHostingController(rootView: env.inject(view))
                controller.sizingOptions = .preferredContentSize
                controller.title = label // the window takes the selected pane's title
                let item = NSTabViewItem(viewController: controller)
                item.label = label
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
                tabs.addTabViewItem(item)
            }
            // Development aid: `--settings-tab N` opens pane N.
            if let i = CommandLine.arguments.firstIndex(of: "--settings-tab"), i + 1 < CommandLine.arguments.count,
               let n = Int(CommandLine.arguments[i + 1]), tabs.tabViewItems.indices.contains(n) {
                tabs.selectedTabViewItemIndex = n
            }
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

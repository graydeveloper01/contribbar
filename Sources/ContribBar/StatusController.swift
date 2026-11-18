import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item and a borderless glass panel that drops down beneath it.
/// (Used instead of MenuBarExtra so we control the window background and its transparency.)
@MainActor
final class StatusController: NSObject {
    private let store: ContributionStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: GlassPanel
    private var snapshotSubscription: AnyCancellable?
    private var themeSubscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var clickMonitor: Any?
    private var lastHidden = Date.distantPast

    init(store: ContributionStore) {
        self.store = store
        panel = GlassPanel(content: PopoverView().environmentObject(store))
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.imagePosition = .imageLeading
        }
        snapshotSubscription = store.$snapshot.sink { [weak self] in self?.updateButton($0) }
        // Applying the theme to the window (not just SwiftUI) also switches the glass and the AppKit-backed colors.
        themeSubscription = UserDefaults.standard.publisher(for: \.theme).sink { [weak self] value in
            self?.panel.appearance = (Theme(rawValue: value) ?? .system).nsAppearance
        }

        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        })
    }

    private func updateButton(_ snapshot: ContributionSnapshot?) {
        guard let button = statusItem.button else { return }
        if let snapshot {
            button.image = MenuBarIcon.image(for: snapshot.last(7))
            button.title = " \(snapshot.today.contributionCount)"
        } else {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "GitHub contributions")
            button.title = ""
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else if Date.now.timeIntervalSince(lastHidden) > 0.3 {
            // Clicking the icon while open can resign key (hiding the panel) just before this action fires.
            showPanel()
        }
    }

    private func showPanel() {
        Task { await store.refreshIfStale() }
        reposition()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        statusItem.button?.highlight(true)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        lastHidden = .now
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// Centers the panel under the menu bar icon, keeping it on screen.
    private func reposition() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let width = panel.frame.width
        let x = min(max(anchor.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - 6))
    }
}

final class GlassPanel: NSPanel {
    init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PopoverView.width, height: 400),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        // The SwiftUI content has a fixed size; size the panel once and never let SwiftUI resize the window.
        let host = NSHostingController(rootView: AnyView(content))
        host.sizingOptions = []
        contentViewController = host
        setContentSize(host.sizeThatFits(in: CGSize(width: PopoverView.width, height: .greatestFiniteMagnitude)))
    }

    override var canBecomeKey: Bool { true }  // needed for the token text field

    override func cancelOperation(_ sender: Any?) {  // Esc closes
        orderOut(nil)
    }
}

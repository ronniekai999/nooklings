import AppKit
import SwiftUI

@main
struct NooklingsApp: App {
    // The adaptor constructs the (main-actor) delegate on the main actor for us,
    // which avoids the actor-isolation error you get from top-level `AppDelegate()`.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible primary window — the delegate builds the notch window itself.
        Settings { EmptyView() }
    }
}

/// Borderless windows can't become key by default, which breaks SwiftUI text
/// input, gestures and context menus. Allow it.
final class NotchWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NotchWindow!
    let model = ByteModel()

    private var expanded = false
    private let compact = NSSize(width: 220, height: 170)
    private var opened: NSSize {
        let d = AppPreferences.shared
        return NSSize(width: max(360, min(1000, d.double(forKey: "byte.panelWidth"))),
                      height: d.object(forKey: "byte.panelHeight") == nil ? 560 : max(480, min(1200, d.double(forKey: "byte.panelHeight"))))
    }

    // Pinned position (top-center anchor in global screen coords), persisted.
    private var dragStartOrigin = CGPoint.zero
    private let pinnedKey  = "byte.pinned"
    private let pinXKey    = "byte.pinX"
    private let pinTopYKey = "byte.pinTopY"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon

        let hosting = NSHostingView(rootView: ByteView(model: model))

        let window = NotchWindow(
            contentRect: NSRect(origin: .zero, size: compact),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                     .fullScreenAuxiliary, .ignoresCycle]
        self.window = window
        window.delegate = self

        position()
        window.orderFrontRegardless()

        // Grow/shrink the window when the chat panel opens or closes.
        model.onChatOpenChanged = { [weak self] open in self?.setExpanded(open) }
        model.onFocusChat = { [weak self] in
            self?.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        model.shortcut.start { [weak self] in self?.model.openAndFocusChat() }
        model.onResizeChat = { [weak self] delta in self?.resizeChat(by: delta) }

        // Drag-to-move / pin-anywhere.
        model.onDragBegan     = { [weak self] in self?.dragBegan() }
        model.onDragChanged   = { [weak self] t in self?.dragChanged(t) }
        model.onDragEnded     = { [weak self] in self?.dragEnded() }
        model.onResetPosition = { [weak self] in self?.resetPosition() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // accessory app keeps running with no standard windows
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForTermination()
        model.shortcut.stop()
    }

    @objc private func screensChanged() { position() }

    private func setExpanded(_ open: Bool) {
        guard expanded != open else { return }
        expanded = open
        window.styleMask = open ? [.borderless, .resizable] : [.borderless]
        position(animated: true)
    }

    /// Place the window so its top-center sits at the pinned anchor — or, if Byte
    /// hasn't been moved, at the top-center of the notched display. The window is
    /// kept fully on whichever display the anchor lands on.
    private func position(animated: Bool = false) {
        let size = expanded ? opened : compact
        let (ax, aTop) = anchorPoint()
        guard let frame = WindowPlacement.frame(anchor: CGPoint(x: ax, y: aTop), size: size,
                                                displays: NSScreen.screens.map(\.visibleFrame)) else { return }
        window.minSize = NSSize(width: min(360, frame.width), height: min(480, frame.height))
        window.setFrame(frame, display: true,
                        animate: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Top-center anchor: the user's pinned point if set, else the notch.
    private func anchorPoint() -> (CGFloat, CGFloat) {
        let d = AppPreferences.shared
        if d.bool(forKey: pinnedKey),
           d.object(forKey: pinXKey) != nil, d.object(forKey: pinTopYKey) != nil {
            return (CGFloat(d.double(forKey: pinXKey)), CGFloat(d.double(forKey: pinTopYKey)))
        }
        let s = notchedScreen() ?? NSScreen.main
        return (s?.visibleFrame.midX ?? 0, s?.visibleFrame.maxY ?? 0)
    }

    // MARK: - Drag to move / pin

    private func dragBegan() { dragStartOrigin = window.frame.origin }

    private func dragChanged(_ t: CGSize) {
        // SwiftUI translation grows down/right; window origin grows up/right.
        let o = CGPoint(x: dragStartOrigin.x + t.width,
                        y: dragStartOrigin.y - t.height)
        let s = window.frame.size
        if let frame = WindowPlacement.frame(anchor: CGPoint(x: o.x + s.width / 2, y: o.y + s.height),
                                             size: s, displays: NSScreen.screens.map(\.visibleFrame)) {
            window.setFrame(frame, display: true)
        }
    }

    private func dragEnded() {
        let f = window.frame
        let d = AppPreferences.shared
        d.set(true, forKey: pinnedKey)
        d.set(Double(f.midX), forKey: pinXKey)
        d.set(Double(f.maxY), forKey: pinTopYKey)
    }

    /// Forget the pinned spot and snap back under the notch.
    func resetPosition() {
        let d = AppPreferences.shared
        d.set(false, forKey: pinnedKey)
        d.removeObject(forKey: pinXKey)
        d.removeObject(forKey: pinTopYKey)
        position(animated: true)
    }

    private func notchedScreen() -> NSScreen? {
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) { return s }
        return NSScreen.main
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let visible = sender.screen?.visibleFrame.size ?? frameSize
        return NSSize(width: min(visible.width, max(360, frameSize.width)),
                      height: min(visible.height, max(480, frameSize.height)))
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard expanded else { return }
        savePanelSize(); dragEnded()
    }

    private func savePanelSize() {
        AppPreferences.shared.set(window.frame.width, forKey: "byte.panelWidth")
        AppPreferences.shared.set(window.frame.height, forKey: "byte.panelHeight")
    }

    private func resizeChat(by delta: CGSize) {
        guard expanded else { return }
        let f = window.frame
        let size = NSSize(width: max(360, f.width + delta.width), height: max(480, f.height + delta.height))
        if let frame = WindowPlacement.frame(anchor: CGPoint(x: f.midX, y: f.maxY), size: size,
                                             displays: NSScreen.screens.map(\.visibleFrame)) {
            window.setFrame(frame, display: true)
            savePanelSize(); dragEnded()
        }
    }
}

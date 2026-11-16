import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class IslandWindowController {
    private var panel: IslandPanel?
    private let state: IslandState
    private var hosting: IslandHostingView<IslandView>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    init(state: IslandState) {
        self.state = state
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        // Panel stays at full revealed size; only the SwiftUI chrome slides.
        applyFullSizeFrame()
        panel?.orderFrontRegardless()
        startNotchMouseMonitor()
        Log.window.info("Island panel shown (tucked under notch)")
    }

    func reposition() {
        applyFullSizeFrame()
    }

    /// Kept for AppDelegate wiring; panel size no longer changes with presence.
    func updateSizeForExpansion() {
        applyFullSizeFrame()
    }

    private func applyFullSizeFrame() {
        guard let panel, let screen = NSScreen.main else { return }
        panel.setFrame(fullFrame(on: screen), display: true)
    }

    private func fullFrame(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let width = IslandLayout.panelWidth
        let height = IslandLayout.revealedPanelHeight
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func createPanel() {
        let view = IslandView(state: state)
        let initial = fullFrame(on: NSScreen.main ?? NSScreen.screens[0])
        let hostingView = IslandHostingView(rootView: view, state: state)
        hostingView.frame = NSRect(origin: .zero, size: initial.size)
        hostingView.autoresizingMask = [.width, .height]

        let panel = IslandPanel(
            contentRect: initial,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .utilityWindow

        self.hosting = hostingView
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.applyFullSizeFrame()
            }
        }
    }

    private func startNotchMouseMonitor() {
        guard globalMouseMonitor == nil else { return }

        // Global: other apps (Finder drag). Hop to main, then just reveal if inside.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.evaluatePointerOverNotch()
            }
        }

        // Local: already on the app’s event stream; call directly when possible.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            if Thread.isMainThread {
                self?.evaluatePointerOverNotch()
            } else {
                DispatchQueue.main.async { self?.evaluatePointerOverNotch() }
            }
            return event
        }
    }

    private func evaluatePointerOverNotch() {
        guard let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let inside = activeHitZone(on: screen).contains(mouse)
        // One rule: in the zone → reveal. Hover and file-drag use the same path.
        state.setPointerInside(inside, reason: inside ? "hit-zone" : "left-zone")
    }

    private func activeHitZone(on screen: NSScreen) -> NSRect {
        if state.isRevealed, let panel {
            let body = NSRect(
                x: panel.frame.midX - IslandLayout.islandWidth / 2,
                y: panel.frame.maxY - IslandLayout.islandHeight,
                width: IslandLayout.islandWidth,
                height: IslandLayout.islandHeight
            )
            return body.insetBy(dx: -8, dy: -8)
        }
        return notchHitBand(on: screen)
    }

    private func notchHitBand(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let width = IslandLayout.notchHitWidth
        let height = max(IslandLayout.notchHitHeight, screen.safeAreaInsets.top + 8)
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Full-size hosting view: click-through outside the active hit zone while tucked,
/// and AppKit drop targeting so Finder drags reveal + shelf ingest.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    private weak var state: IslandState?

    init(rootView: Content, state: IslandState) {
        self.state = state
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @MainActor required init(rootView: Content) {
        self.state = nil
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // While tucked, only the top notch strip intercepts mouse/drags so the
        // always-full-size panel does not block the desktop below.
        guard let state else { return super.hitTest(point) }
        let zone = hitZoneInViewCoordinates(revealed: state.isRevealed)
        guard zone.contains(point) else { return nil }
        return super.hitTest(point)
    }

    private func hitZoneInViewCoordinates(revealed: Bool) -> NSRect {
        let bounds = self.bounds
        if revealed {
            let x = (bounds.width - IslandLayout.islandWidth) / 2
            let y = bounds.height - IslandLayout.islandHeight
            return NSRect(x: x, y: y, width: IslandLayout.islandWidth, height: IslandLayout.islandHeight)
                .insetBy(dx: -8, dy: -8)
        }
        let width = IslandLayout.notchHitWidth
        let height = IslandLayout.notchHitHeight
        let x = (bounds.width - width) / 2
        let y = bounds.height - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        state?.setPointerInside(true, reason: "drag-enter")
        return canAccept(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        state?.setPointerInside(true, reason: "drag-update")
        return canAccept(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        state?.setPointerInside(false, reason: "drag-exit")
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            state?.setPointerInside(false, reason: "drag-failed")
            return false
        }
        state?.reveal(reason: "appkit-drop")
        state?.shelf.ingest(urls: urls)
        // Keep revealed while the cursor is still over us; mouse monitor will tuck on leave.
        state?.setPointerInside(true, reason: "drag-drop")
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        // Do not force-tuck here; pointer may still be over the island.
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }
}

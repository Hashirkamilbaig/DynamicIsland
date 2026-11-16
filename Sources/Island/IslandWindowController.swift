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
        applyPresenceLayout(animated: false)
        panel?.orderFrontRegardless()
        startNotchMouseMonitor()
        Log.window.info("Island panel shown (tucked under notch)")
    }

    func applyPresenceLayout(animated: Bool) {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = frameOnScreen(screen, revealed: state.isRevealed)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    func reposition() {
        applyPresenceLayout(animated: false)
    }

    func updateSizeForExpansion() {
        applyPresenceLayout(animated: true)
    }

    private func frameOnScreen(_ screen: NSScreen, revealed: Bool) -> NSRect {
        // Full screen frame includes the menu-bar / notch band (visibleFrame does not).
        let screenFrame = screen.frame
        let width = IslandLayout.panelWidth
        // Revealed panel is taller than the island so the soft shadow below is not clipped;
        // the island itself is top-aligned and flush with screen.maxY.
        let height = revealed ? IslandLayout.revealedPanelHeight : IslandLayout.notchHitHeight
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func createPanel() {
        let view = IslandView(state: state)
        let initial = frameOnScreen(NSScreen.main ?? NSScreen.screens[0], revealed: false)
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
        // Above the menu bar so the notch hit target receives mouse/drag events.
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
            Task { @MainActor in
                self?.applyPresenceLayout(animated: false)
            }
        }
    }

    private func startNotchMouseMonitor() {
        guard globalMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePointerOverNotch()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in
                self?.evaluatePointerOverNotch()
            }
            return event
        }
    }

    private func evaluatePointerOverNotch() {
        guard let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation

        // While revealed, the interactive zone is the island body (not the shadow padding alone).
        let zone: NSRect
        if state.isRevealed, let panel {
            // Island is top-aligned inside the panel; ignore bottom shadow padding for hit-testing.
            let body = NSRect(
                x: panel.frame.midX - IslandLayout.islandWidth / 2,
                y: panel.frame.maxY - IslandLayout.islandHeight,
                width: IslandLayout.islandWidth,
                height: IslandLayout.islandHeight
            )
            zone = body.insetBy(dx: -6, dy: -6)
        } else {
            zone = notchHitBand(on: screen)
        }

        let inside = zone.contains(mouse)
        let dragInProgress = NSEvent.pressedMouseButtons != 0

        if inside {
            if dragInProgress {
                state.handleDragTargeted(true)
            } else {
                state.handleHover(true)
            }
        } else {
            if state.isHovering {
                state.handleHover(false)
            }
            if state.isDragTargeted {
                state.handleDragTargeted(false)
            }
        }
    }

    private func notchHitBand(on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let width = IslandLayout.notchHitWidth
        let height = max(IslandLayout.notchHitHeight, screen.safeAreaInsets.top + 4)
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

/// AppKit drop destination so Finder drags reveal the tucked island and land on the shelf.
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Task { @MainActor in
            state?.handleDragTargeted(true)
        }
        return canAccept(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Task { @MainActor in
            state?.handleDragTargeted(true)
        }
        return canAccept(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        Task { @MainActor in
            state?.handleDragTargeted(false)
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            Task { @MainActor in
                state?.handleDragTargeted(false)
            }
            return false
        }
        Task { @MainActor in
            state?.reveal(reason: "appkit-drop")
            state?.shelf.ingest(urls: urls)
            state?.handleDragTargeted(false)
        }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        Task { @MainActor in
            state?.handleDragTargeted(false)
        }
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }
}

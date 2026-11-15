import AppKit
import SwiftUI

@MainActor
final class IslandWindowController {
    private var panel: IslandPanel?
    private let state: IslandState
    private var hosting: NSHostingView<IslandView>?

    init(state: IslandState) {
        self.state = state
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        reposition()
        panel?.orderFrontRegardless()
        Log.window.info("Island panel shown")
    }

    func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func updateSizeForExpansion() {
        guard let panel else { return }
        let expanded = state.expansion == .expanded
        let size = NSSize(width: expanded ? 420 : 220, height: expanded ? 168 : 34)
        var frame = panel.frame
        let screen = NSScreen.main?.visibleFrame ?? panel.frame
        frame.size = size
        frame.origin.x = screen.midX - size.width / 2
        frame.origin.y = screen.maxY - size.height - 8
        panel.setFrame(frame, display: true, animate: true)
    }

    private func createPanel() {
        let view = IslandView(state: state)
        let initialFrame = NSRect(x: 0, y: 0, width: 220, height: 34)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = initialFrame
        hostingView.autoresizingMask = [.width, .height]

        let panel = IslandPanel(
            contentRect: initialFrame,
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
            Task { @MainActor in
                self?.reposition()
            }
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

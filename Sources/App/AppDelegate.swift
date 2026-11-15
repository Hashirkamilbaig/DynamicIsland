import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: IslandState?
    private var windowController: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Dynamic Island launching")

        let state = IslandState()
        state.start()
        self.state = state

        let controller = IslandWindowController(state: state)
        controller.show()
        self.windowController = controller

        state.$expansion
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.windowController?.updateSizeForExpansion()
            }
            .store(in: &cancellables)

        installStatusItem()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.shelf.clearAll()
        state?.nowPlaying.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "capsule.portrait.fill", accessibilityDescription: "Dynamic Island")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Island", action: #selector(showIsland), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Toggle Expand", action: #selector(toggleIsland), keyEquivalent: "e"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dynamic Island", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func showIsland() {
        windowController?.show()
    }

    @objc private func toggleIsland() {
        state?.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

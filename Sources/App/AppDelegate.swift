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

        state.$presence
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.windowController?.updateSizeForExpansion()
            }
            .store(in: &cancellables)

        state.nowPlaying.onNeedsSpotifyConnection = { [weak self] in self?.connectSpotify() }
        state.nowPlaying.onError = { [weak self] message in self?.showAlert("New songs after this", message) }

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
        menu.addItem(NSMenuItem(title: "Reveal / Hide", action: #selector(toggleIsland), keyEquivalent: "e"))
        menu.addItem(.separator())
        menu.addItem(spotifyMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dynamic Island", action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func showIsland() {
        state?.reveal(reason: "menu-show")
        windowController?.show()
    }

    @objc private func toggleIsland() {
        state?.toggleFromMenu()
    }

    private lazy var spotifyMenuItem = NSMenuItem(title: "Connect Spotify…", action: #selector(toggleSpotifyConnection), keyEquivalent: "")

    @objc private func toggleSpotifyConnection() {
        guard let api = state?.nowPlaying.spotifyAPI else { return }
        if api.isConnected {
            api.disconnect()
        } else {
            connectSpotify()
        }
    }

    private func connectSpotify() {
        guard let api = state?.nowPlaying.spotifyAPI else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Connect Spotify"
        alert.informativeText = """
        "New songs after this" needs to know which playlist is playing, which only Spotify's Web API can tell.

        1. Open developer.spotify.com/dashboard and create an app.
        2. Add this Redirect URI: \(SpotifyWebAPI.redirectURI)
        3. Tick "Web API", save, and paste the app's Client ID below.
        """
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Client ID"
        field.stringValue = api.clientID ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Open Dashboard")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let id = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return }
            api.connect(clientID: id)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
        default:
            break
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let connected = state?.nowPlaying.spotifyAPI.isConnected ?? false
        spotifyMenuItem.title = connected ? "Disconnect Spotify" : "Connect Spotify…"
    }
}

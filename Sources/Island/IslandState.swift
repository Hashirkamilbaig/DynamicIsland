import Foundation
import Combine
import AppKit

@MainActor
final class IslandState: ObservableObject {
    /// Tucked = parked under the notch. Revealed = slid out for interaction.
    enum Presence: Equatable {
        case tucked
        case revealed
    }

    @Published var presence: Presence = .tucked
    @Published var isHovering = false
    @Published var isDragTargeted = false

    let shelf: ShelfStore
    let nowPlaying: NowPlayingService
    let volume: SystemVolumeService

    private var cancellables = Set<AnyCancellable>()
    private var tuckWorkItem: DispatchWorkItem?

    var isRevealed: Bool { presence == .revealed }

    init() {
        self.shelf = ShelfStore()
        self.nowPlaying = NowPlayingService()
        self.volume = SystemVolumeService()
        self.observeChildren()
    }

    init(shelf: ShelfStore, nowPlaying: NowPlayingService, volume: SystemVolumeService) {
        self.shelf = shelf
        self.nowPlaying = nowPlaying
        self.volume = volume
        self.observeChildren()
    }

    private func observeChildren() {
        shelf.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        nowPlaying.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        volume.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        nowPlaying.start()
        volume.refresh()
    }

    /// Bring the island out from under the notch.
    func reveal(reason: String) {
        tuckWorkItem?.cancel()
        if presence != .revealed {
            Log.window.debug("Reveal (\(reason, privacy: .public))")
        }
        presence = .revealed
    }

    /// Park the island back under the notch.
    func tuck(reason: String) {
        tuckWorkItem?.cancel()
        if presence != .tucked {
            Log.window.debug("Tuck (\(reason, privacy: .public))")
        }
        presence = .tucked
    }

    /// Menu-bar helper only. Clicks on the island itself must not dismiss.
    func toggleFromMenu() {
        if isRevealed {
            tuck(reason: "menu")
        } else {
            reveal(reason: "menu")
        }
    }

    func handleHover(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            reveal(reason: "hover")
        } else {
            scheduleTuckIfIdle(after: 0.35)
        }
    }

    func handleDragTargeted(_ targeted: Bool) {
        isDragTargeted = targeted
        if targeted {
            reveal(reason: "drag")
        } else {
            scheduleTuckIfIdle(after: 0.45)
        }
    }

    private func scheduleTuckIfIdle(after delay: TimeInterval) {
        tuckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Stay out while the pointer or an active file drag is over the island.
            if !self.isHovering, !self.isDragTargeted {
                self.tuck(reason: "pointer-left")
            }
        }
        tuckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

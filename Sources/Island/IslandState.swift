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

    @Published private(set) var presence: Presence = .tucked
    /// True while the cursor (or an active file drag) is inside the island hit zone.
    @Published private(set) var isPointerInside = false

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

    /// Single rule: pointer in the hit zone → always reveal. Leave → tuck after a short delay.
    func setPointerInside(_ inside: Bool, reason: String) {
        isPointerInside = inside
        if inside {
            reveal(reason: reason)
        } else {
            scheduleTuckIfIdle(after: 0.25)
        }
    }

    func reveal(reason: String) {
        tuckWorkItem?.cancel()
        guard presence != .revealed else { return }
        Log.window.debug("Reveal (\(reason, privacy: .public))")
        presence = .revealed
    }

    func tuck(reason: String) {
        tuckWorkItem?.cancel()
        guard presence != .tucked else { return }
        Log.window.debug("Tuck (\(reason, privacy: .public))")
        presence = .tucked
    }

    /// Menu-bar helper only. Clicks on the island itself must not dismiss.
    func toggleFromMenu() {
        if isRevealed {
            isPointerInside = false
            tuck(reason: "menu")
        } else {
            reveal(reason: "menu")
        }
    }

    private func scheduleTuckIfIdle(after delay: TimeInterval) {
        tuckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.isPointerInside {
                self.tuck(reason: "pointer-left")
            }
        }
        tuckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

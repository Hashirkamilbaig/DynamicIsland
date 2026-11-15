import Foundation
import Combine
import AppKit

@MainActor
final class IslandState: ObservableObject {
    enum Expansion: Equatable {
        case collapsed
        case expanded
    }

    @Published var expansion: Expansion = .collapsed
    @Published var isHovering = false

    let shelf: ShelfStore
    let nowPlaying: NowPlayingService
    let volume: SystemVolumeService

    private var cancellables = Set<AnyCancellable>()
    private var collapseWorkItem: DispatchWorkItem?

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

        shelf.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                guard let self else { return }
                if !items.isEmpty {
                    self.expand(reason: "shelf")
                } else if self.expansion == .expanded, !self.isHovering {
                    self.scheduleCollapse(after: 1.2)
                }
            }
            .store(in: &cancellables)
    }

    func start() {
        nowPlaying.start()
        volume.refresh()
    }

    func expand(reason: String) {
        collapseWorkItem?.cancel()
        if expansion != .expanded {
            Log.window.debug("Expand (\(reason, privacy: .public))")
        }
        expansion = .expanded
    }

    func collapse(reason: String) {
        collapseWorkItem?.cancel()
        guard shelf.items.isEmpty else { return }
        if expansion != .collapsed {
            Log.window.debug("Collapse (\(reason, privacy: .public))")
        }
        expansion = .collapsed
    }

    func toggle() {
        if expansion == .expanded {
            collapse(reason: "toggle")
        } else {
            expand(reason: "toggle")
        }
    }

    func handleHover(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            expand(reason: "hover")
        } else {
            scheduleCollapse(after: 0.8)
        }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.isHovering, self.shelf.items.isEmpty {
                self.collapse(reason: "idle")
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

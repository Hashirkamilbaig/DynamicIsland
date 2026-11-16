import Foundation

/// The combined shuffle / repeat button. Spotify exposes only on/off for each
/// over AppleScript, so Smart Shuffle and repeat-one aren't reachable.
enum PlayMode: CaseIterable, Equatable {
    case off
    case shuffle
    case repeatAll

    init(shuffling: Bool, repeating: Bool) {
        if shuffling {
            self = .shuffle
        } else if repeating {
            self = .repeatAll
        } else {
            self = .off
        }
    }

    var next: PlayMode {
        let all = PlayMode.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    var shuffling: Bool { self == .shuffle }
    var repeating: Bool { self == .repeatAll }

    var symbol: String { self == .repeatAll ? "repeat" : "shuffle" }

    var label: String {
        switch self {
        case .off: return "Shuffle and repeat off"
        case .shuffle: return "Shuffle on"
        case .repeatAll: return "Repeat on"
        }
    }
}

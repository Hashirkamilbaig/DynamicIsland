import CoreGraphics

enum IslandLayout {
    /// Expanded island width (wider than the hardware notch so it can swallow it).
    static let islandWidth: CGFloat = 520
    /// Full revealed height including the top band that covers the notch.
    static let islandHeight: CGFloat = 196
    /// Extra transparent margin so the soft outer shadow is not clipped by the panel.
    static let shadowPadding: CGFloat = 28
    static let panelWidth: CGFloat = islandWidth + shadowPadding * 2
    static let revealedPanelHeight: CGFloat = islandHeight + shadowPadding
    /// Clearance under the physical camera notch before content begins.
    static let notchClearance: CGFloat = 34
    static let bottomCornerRadius: CGFloat = 42
    /// Approximate radius of the hardware notch's bottom corners.
    static let notchCornerRadius: CGFloat = 10
    static let artSize: CGFloat = 92
    static let shelfWidth: CGFloat = 150

    /// Notch sensor while tucked. Tiny on purpose; reveal uses only this rect
    /// (mouse monitor + AppKit hitTest), not the full panel frame.
    /// Fallback for displays without a notch (14" MacBook Pro notch size).
    static let notchHitWidth: CGFloat = 185
    static let notchHitHeight: CGFloat = 32
}

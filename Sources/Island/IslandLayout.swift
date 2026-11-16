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
    static let artSize: CGFloat = 92

    /// Notch sensor while tucked.
    static let notchHitWidth: CGFloat = 22.5
    static let notchHitHeight: CGFloat = 2.75
    /// Pull chrome upward so it sits under the notch when tucked.
    static let tuckedOffsetY: CGFloat = -islandHeight
}

import AppKit

extension NSScreen {
    /// Physical notch size in points, measured from the menu-bar areas beside it.
    /// Falls back to IslandLayout constants on displays without a notch.
    var notchSize: CGSize {
        guard let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea,
              safeAreaInsets.top > 0 else {
            return CGSize(width: IslandLayout.notchHitWidth, height: IslandLayout.notchHitHeight)
        }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

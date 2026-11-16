# Dynamic Island (macOS)

Floating island that stays tucked under the Mac notch until the pointer enters the notch region, with:

1. **File shelf** — drop files in, drag them out for ~20 seconds, then they auto-purge
2. **Now Playing** — title / artist / artwork plus play, pause, next, previous
3. **System volume** — Mac output-device volume (Core Audio), not Spotify’s in-app volume

Native Swift + SwiftUI. No Electron.

## Open & run

1. Open `DynamicIsland.xcodeproj` in Xcode.
2. Select the **DynamicIsland** scheme and **My Mac**.
3. Press **⌘R**.

Or from Terminal:

```bash
cd ~/Desktop/DynamicIsland
xcodebuild -scheme DynamicIsland -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/DynamicIsland.app
```

Signing: Debug uses ad-hoc identity (`CODE_SIGN_IDENTITY = "-"`) so a free Apple ID / local Run works. If Xcode asks for a team, pick your Personal Team; paid Developer Program is not required for local use.

## Permissions

| Permission | When needed |
| --- | --- |
| **Automation → Spotify** | Only if MediaRemote fails and the AppleScript fallback talks to Spotify |
| **Accessibility** | Optional; reserved for future global hotkeys (`Permissions.swift`) |

No Full Disk Access. Shelf files live under `~/Library/Caches/DynamicIsland/Shelf/`.

The app is an agent (`LSUIElement`): no Dock icon. Use the menu-bar capsule icon → **Reveal / Hide** / **Quit**.

Interaction: the island does not dismiss on click. It reveals when the cursor (or a file drag) enters the notch band, and tucks again when the pointer leaves.

## Folder map

```
Sources/
  App/        entry + AppDelegate (menu bar, lifecycle)
  Island/     NSPanel host, SwiftUI island, shared state
  Shelf/      ingest, 20s TTL, drop / drag UI
  Media/      Now Playing + MediaRemoteBridge (private API isolated here)
  Volume/     Core Audio device volume + mute
  Support/    Logger categories, permissions helpers
Tests/        shelf TTL + volume clamp
Resources/    Info.plist, entitlements, assets
```

Debug with Console.app filters on subsystem `com.hashir.DynamicIsland` and categories `shelf`, `media`, `volume`, `window`.

## How to debug

### Shelf TTL

- Change `ShelfStore.defaultTTL` (default `20`).
- Watch logs: `Ingested … expires in 20s` then `Purged N expired shelf item(s)`.
- Cache path: `~/Library/Caches/DynamicIsland/Shelf/`.
- Unit test: `ShelfStoreTests`.

### System volume

- `SystemVolumeService` reads/writes `kAudioDevicePropertyVolumeScalar` on the default output device.
- Move the island slider; system volume should change while Spotify’s own volume stays put.
- Unit test: `SystemVolumeServiceTests.testClampBounds`.

### Now Playing

- Primary path: `MediaRemoteBridge.swift` (private MediaRemote framework).
- Fallback: Spotify AppleScript in `NowPlayingService` (needs Automation permission).
- If artwork/title is empty, confirm something is actually playing, then check `media` logs for missing symbols.

## v1 success checks

- Drop a PDF on the island → drag into Mail within 20s → works; after 20s the chip is gone.
- Play Spotify → island shows track; skip/pause work; volume slider moves **Mac** volume.

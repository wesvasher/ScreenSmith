# ScreenSmith

A macOS menu bar app for switching display resolutions. It has no Dock icon or main window (`LSUIElement = YES`). Every connected monitor gets a submenu listing its Retina and Standard modes, and a Presets submenu saves and restores the resolutions of all attached displays. A Settings window (sidebar: Settings, Presets, then one page per connected display) holds the app options and per-display nickname, icon and hardware details.

Originally written with Google Gemini; development continued with Claude Code.

## Layout

- `ScreenSmith/ScreenSmithApp.swift` — the `MenuBarExtra` (menu style) and the single `Settings` `Window` scene (`defaultLaunchBehavior(.suppressed)`, so it never opens at launch). Displays are renamed on their Settings page; the menu has no Rename item.
- `ScreenSmith/SettingsView.swift` — the Settings window: a `NavigationSplitView` driven by `SettingsNavigation` (shared with the menu), `GeneralSettingsView` (the "Hide refresh rates below" cutoff picker and Start at Login via `SMAppService.mainApp`), and `DisplaySettingsView` (nickname, icon selector, Details, and an Apply Changes button; nickname and icon edits apply only on Apply). In Details, Current Mode is a `ModePicker` popup (`modeGroups(for:minimumRefreshRate:including:)`: Retina/Standard, split by notch when relevant, always including the current mode) that switches resolution immediately, like the menu bar. The icon selector is one row of four selectable cards (Laptop, Monitor, TV, Custom). The selected card gets an accent ring, which slides between cards via `matchedGeometryEffect`, plus a checkmark and a bold title. The custom card's emoji (😀 until changed) is a full-size text field at 0.02 opacity with the emoji drawn over it, so its cursor and selection highlight never show. The field is layered over the card's button and gives up focus when another card is chosen or an emoji is picked. An earlier 1×1 hidden field was unreliable, so keep this one full-size, and its instructions appear below the row only while Custom is selected. The emoji is a real, visible text field because the system emoji picker types into whichever field has focus. The "click here" link under it focuses that field and calls `NSApp.orderFrontCharacterPalette`, and double-clicking an emoji in the picker replaces the custom emoji. Non-emoji input is ignored.
- `ScreenSmith/Presets.swift` — `Preset` / `PresetDisplay` (one saved mode per display, matched by hardware key and `DisplayMode.id`), `PresetStore` (JSON in `UserDefaults`, plus the NSAlert that names a new preset and lists what it captures), and `DisplayManager` helpers to capture, apply and check presets. Applying skips displays that aren't attached; the menu disables presets with none attached and checkmarks the one matching the current setup. The Presets settings page (`PresetsSettingsView`) renames them and changes each attached display's saved resolution with a `ModePicker` (drafts saved only by Apply Changes or Return, like the display pages; displays that aren't attached show plain text) and deletes them (immediately, after a confirmation).
- `ScreenSmith/Rotation.swift` — display rotation. Reading uses the public `CGDisplayRotation`. Setting has no public API, so it goes through the private MonitorPanel framework's `MPDisplay` (`displayID` equals the CGDirectDisplayID; `canChangeOrientation`; `setOrientation:(int)degrees`), called via the Objective-C runtime. It works inside the App Sandbox. If the class or methods disappear, `canRotate` is false and rotation controls are hidden. Rotation appears as a section in each display's menu, a Details popup (immediate) and a per-display preset setting (`PresetDisplay.rotation`, nil in older presets). Applying a preset sets rotation before resolution.
- `ScreenSmith/DisplayInfo.swift` — `DisplayIcon` (the built-in 💻 🖥️ 📺 emoji), `Character.isEmoji`, and the Details rows (model from `NSScreen.localizedName`, size from `CGDisplayScreenSize`, HDR from EDR headroom, serial).
- `ScreenSmith/DisplayManager.swift` — `DisplayManager` (`ObservableObject`) wraps CoreGraphics: lists active displays, reads and sets `CGDisplayMode`s, and persists custom names and icon emoji in `UserDefaults`. Icons stored by an earlier build as names ("laptop", "desktop", "tv") are converted on load; "custom" (an image, no longer supported) is dropped. `DisplayMode` is the view model for a single mode.

There is no test target.

## Build & run

```sh
xcodebuild -project ScreenSmith.xcodeproj -scheme ScreenSmith -configuration Debug build
```

Add `CODE_SIGNING_ALLOWED=NO` for a quick compile check without signing. To run it for real, use a signed build (team `YBN8GSZ6V8`), because login items and the sandbox need one.

`scripts/dev-run.sh` builds a signed Debug copy into `build/DerivedData` and relaunches it, but only if files under `ScreenSmith/` or the project changed since the last successful build (`--force` always rebuilds). A Stop hook in `.claude/settings.json` runs it at the end of every Claude turn. A build failure exits 2, so the compiler errors come back to Claude to fix. Don't launch the app another way during a session; the hook already does it.

## Releasing

`scripts/make-dmg.sh` builds a universal (arm64 + x86_64) Release copy into `build/release` and packages `build/ScreenSmith-<version>.dmg` (the app plus an Applications link). The app is ad-hoc signed and not notarized, because there's no paid Apple Developer account, so users approve it via Privacy & Security › Open Anyway; the README and release notes say so. `--publish` also creates GitHub release `v<version>` with the DMG attached, after checking the tree is clean and matches `origin/main`. The version is `MARKETING_VERSION` in the Xcode project; bump it before each release. Build with `-destination "generic/platform=macOS"`, otherwise xcodebuild builds only this Mac's architecture.

## Project settings to know

- Deployment target is **macOS 26.1**, so new macOS APIs can be used freely.
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`: a file must import a module itself to use its members, e.g. `import Combine` for `ObservableObject`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: everything is main-actor isolated by default. Passing an initializer reference like `.map(DisplayMode.init)` warns; use a closure instead (`.map { DisplayMode($0) }`).
- App Sandbox is on.
- The project uses file-system-synchronized groups (`objectVersion = 77`). Adding or deleting a `.swift` file under `ScreenSmith/` needs no `project.pbxproj` edit.

## Icons

HiDPI and standard modes are marked with custom template icons in `Assets.xcassets`, not SF Symbols. There are three pairs, each a smooth `.hidpi` shape and a pixelated `.standard` one: `density.curve.*` (an arc vs a pixel staircase, currently used), `density.ring.*` (a bordered circle) and `density.circle.*` (a solid disc). The unused pairs are kept as alternatives. `DisplayMode.iconName(hiDPI:)` is the single place that chooses them. The SVGs are drawn on a 16×16 grid; the pixelated versions use 2×2 cells. SwiftUI menus only show a `Label`'s icon with `.labelStyle(.titleAndIcon)`, and always on the left. Right-aligning icons would mean rebuilding the menu in AppKit, which was considered and declined.

## Behaviors worth preserving

- **Custom names and icons are keyed by hardware identity**, `"<vendor>-<model>-<serial>"` (or `unit<N>` when the serial is 0), not by `CGDirectDisplayID`, which changes across reboots and reconnects. Older builds used the raw display ID as the key; `migrateLegacyNames()` converts those once the matching display is connected.
- **The display list refreshes on `NSApplication.didChangeScreenParametersNotification`**, so hot-plugging monitors works without relaunching.
- **Mode lists are deduplicated** by `DisplayMode.id` (width, height, rounded refresh rate, HiDPI), and only modes with `isUsableForDesktopGUI()` are shown.
- **Native resolution comes from `kDisplayModeNativeFlag` (0x02000000 in `ioFlags`)**, not from the largest mode. macOS also lists supersampled modes larger than the panel (6720×3780 on a 3840×2160 Dell, 4112×2658 on the 16" MacBook Pro). `nativePixelSize(for:)` feeds the "Native Resolution" detail row, and the menu tags modes whose backing pixels equal it: "· Native" (1:1) or "· Native (2×)" (Retina).
- **Notched built-in panels get split mode lists.** `notchPanelAspect(for:)` returns the native height/width shape (from `nativePixelSize`, falling back to the highest-pixel mode) only when a built-in panel is taller than 16:10 and also offers 16:10 modes. Just checking for "modes of another shape" misfired on a non-notched 2020 16" MacBook Pro (16:10 panel with one odd 825×525 mode). Modes with the native shape (≈0.646 on a 16" MacBook Pro) fill the panel around the notch; the 16:10 ones (0.625) are letterboxed below it. The menu shows them under "Full panel (notch)" and "Below notch (no notch)" sections, and Details gains a Notch row. Other displays are unchanged. `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` only describe the current mode, so they can't classify the others.
- **"Move Menu Bar to This Display" (`makeMainDisplay`) works the way System Settings does:** the main display is whichever sits at the global origin, so it moves the chosen display to (0, 0) and shifts every other non-mirrored display by the same offset in one `CGBeginDisplayConfiguration` … `.permanently` transaction, keeping the arrangement intact. It's disabled for mirroring displays. The sidebar marks the main display with `menubar.rectangle`.
- **An empty nickname resets the display to its default name.**
- **The refresh filter is a cutoff in Hz** (`RefreshFilter`, `UserDefaults` key `minimumRefreshRate`, 0 = off). The menu hides modes whose rounded rate is below it. The old on/off `showOnlyHighRefresh` setting is migrated to 60 at launch. Settings are in the sandbox container (`~/Library/Containers/vasher.ScreenSmith`), which `defaults read` and `plutil` can't open from outside the app.
- **The Start at Login toggle reflects `SMAppService.status` after each attempt** instead of the requested value. If macOS needs approval, it opens System Settings › Login Items.

## Known gaps

- The README had a header image (`Images/Github/header-1.png`) that was never committed. It was removed until the image is added to the repo.
- Non-main displays fall back to the name `External Display (<id>)`; `NSScreen.localizedName` would be friendlier.

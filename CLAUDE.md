# ScreenSmith

A macOS menu bar app for switching display resolutions. It has no Dock icon or main window (`LSUIElement = YES`). Every connected monitor gets a submenu listing its Retina and Standard modes, plus options to rename it, filter to high refresh rates, start at login, and open System Display Settings.

Originally written with Google Gemini; development continued with Claude Code.

## Layout

- `ScreenSmith/ScreenSmithApp.swift` — the whole UI: a `MenuBarExtra` (menu style) plus a small "Rename Display" `WindowGroup`. Also owns the Start at Login toggle (`SMAppService.mainApp`).
- `ScreenSmith/DisplayManager.swift` — `DisplayManager` (`ObservableObject`) wraps CoreGraphics: lists active displays, reads and sets `CGDisplayMode`s, and persists custom names in `UserDefaults`. `DisplayMode` is the view model for a single mode.

There is no test target.

## Build & run

```sh
xcodebuild -project ScreenSmith.xcodeproj -scheme ScreenSmith -configuration Debug build
```

Add `CODE_SIGNING_ALLOWED=NO` for a quick compile check without signing. To run it for real, open it in Xcode (team `YBN8GSZ6V8`), because login items and the sandbox need a signed build.

## Project settings to know

- Deployment target is **macOS 26.1**, so new macOS APIs can be used freely.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: everything is main-actor isolated by default. Passing an initializer reference like `.map(DisplayMode.init)` warns; use a closure instead (`.map { DisplayMode($0) }`).
- App Sandbox is on.
- The project uses file-system-synchronized groups (`objectVersion = 77`). Adding or deleting a `.swift` file under `ScreenSmith/` needs no `project.pbxproj` edit.

## Behaviors worth preserving

- **Custom names are keyed by hardware identity**, `"<vendor>-<model>-<serial>"` (or `unit<N>` when the serial is 0), not by `CGDirectDisplayID`, which changes across reboots and reconnects. Older builds used the raw display ID as the key; `migrateLegacyNames()` converts those once the matching display is connected.
- **The display list refreshes on `NSApplication.didChangeScreenParametersNotification`**, so hot-plugging monitors works without relaunching.
- **Mode lists are deduplicated** by `DisplayMode.id` (width, height, rounded refresh rate, HiDPI), and only modes with `isUsableForDesktopGUI()` are shown.
- **The Start at Login toggle reflects `SMAppService.status` after each attempt** instead of the requested value. If macOS needs approval, it opens System Settings › Login Items.

## Known gaps

- The README had a header image (`Images/Github/header-1.png`) that was never committed. It was removed until the image is added to the repo.
- Non-main displays fall back to the name `External Display (<id>)`; `NSScreen.localizedName` would be friendlier.
- Saving an empty name in the Rename window stores an empty string instead of resetting the name.

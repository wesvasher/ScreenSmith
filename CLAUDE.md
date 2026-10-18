# ScreenSmith

macOS menu bar app (no Dock icon, `LSUIElement`) for switching display resolutions and rotation, with presets and a Settings window. Started with Gemini; continued with Claude Code.

## Files

- `ScreenSmithApp.swift`: the `MenuBarExtra` menu and the Settings `Window` (suppressed at launch).
- `SettingsView.swift`: Settings sidebar and pages (general, presets, one per display), plus shared `ModePicker` / `RotationPicker`.
- `DisplayManager.swift`: CoreGraphics wrapper; displays, modes, names, icons, main display.
- `DisplayInfo.swift`: Details rows, native resolution, notch detection, emoji icons, refresh cutoff.
- `Presets.swift`: preset model, storage, capture and apply.
- `Rotation.swift`: rotation through the private MonitorPanel framework.

No test target.

## Workflow

- `scripts/dev-run.sh` builds a signed Debug copy into `build/` and relaunches it when sources changed (`--force` always rebuilds). A Stop hook in `.claude/settings.json` runs it after every turn, and build errors are reported back. Don't launch the app another way.
- Release: bump `MARKETING_VERSION` by .01 (1.01, 1.02 … 1.10) and `CURRENT_PROJECT_VERSION` by 1, commit and push, then run `scripts/make-dmg.sh --publish`. It builds a universal, ad-hoc-signed (not notarized) DMG and creates the GitHub release.
- The user commits straight to `main` (solo project). Commit and push only when asked.

## Project settings

- macOS 26.1 deployment target; App Sandbox on.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: use closures, not initializer references like `.map(DisplayMode.init)`.
- Member import visibility is on: each file imports what it uses (e.g. `Combine` for `ObservableObject`).
- File-system-synchronized groups: adding a file under `ScreenSmith/` needs no project edit.
- Sandboxed settings live in `~/Library/Containers/vasher.ScreenSmith`, which can't be read from the terminal.

## Non-obvious decisions

- **Displays are identified by hardware key** (`vendor-model-serial`), not `CGDirectDisplayID`, which changes across reboots. Names, icons and presets all use it.
- **Native resolution** comes from `kDisplayModeNativeFlag`, not the largest mode. macOS lists supersampled modes bigger than the panel.
- **Notch detection:** a built-in panel taller than 16:10 that also offers 16:10 modes. A looser rule misfired on a 2020 16" MacBook Pro.
- **Rotation** has no public setter. It uses `MPDisplay.setOrientation:` from MonitorPanel, which works in the sandbox. Rotation support is cached when displays change, because creating `MPDisplayMgr` while the menu is built is expensive.
- **Main display** = the display at the global origin. `makeMainDisplay` shifts all displays in one configuration transaction, like System Settings.
- **The custom emoji field** must be a real, full-size text field: the system emoji picker types into the focused field, and a 1×1 hidden field didn't work. It's kept at 0.02 opacity with the emoji drawn on top, so its cursor never shows.
- **Edits:** on the Settings display and preset pages, edits are drafts until Apply Changes. Resolution, rotation and main-display changes on a display's page apply immediately.
- **Menu icons:** SwiftUI menus show `Label` icons only with `.labelStyle(.titleAndIcon)`, and only on the left. Right-aligning them would mean an AppKit rewrite, which was declined. Bold text in menu titles is stripped too.
- **Icons:** the HiDPI/standard markers are template SVGs in `Assets.xcassets` (`density.curve.*` in use; `ring` and `circle` pairs kept). The app icon is `ScreenSmith.icon`; edit it in Icon Composer.

## Known gaps

- Displays without a nickname are named "Main Display" / "External Display (<id>)"; `NSScreen.localizedName` would be friendlier.
- If the menu ever opens with a gap below the menu bar in every third-party app, that's stale macOS state, not ScreenSmith. A restart fixes it.

import SwiftUI

@main
struct ScreenSmithApp: App {
    @StateObject private var manager = DisplayManager()
    @StateObject private var settingsNavigation = SettingsNavigation()
    @StateObject private var presetStore = PresetStore()
    @AppStorage(RefreshFilter.key) private var minimumRefreshRate = 0
    @Environment(\.openWindow) private var openWindow

    init() {
        RefreshFilter.migrateLegacySetting()
    }

    var body: some Scene {
        MenuBarExtra("ScreenSmith", systemImage: "display") {
            ForEach(Array(manager.displays.enumerated()), id: \.element) { index, displayID in
                let displayName = manager.getDisplayName(for: displayID)
                let displayTitle = "\(manager.icon(for: displayID)) \(displayName)"
                let current = manager.getCurrentMode(for: displayID)
                let allModes = manager.getModes(for: displayID)

                Menu {
                    if let cur = current {
                        Text("Active: \(cur.width) x \(cur.height) @ \(Int(cur.refreshRate.rounded()))Hz")
                    }

                    let filtered = allModes.filter { Int($0.refreshRate.rounded()) >= minimumRefreshRate }
                    let retinaModes = filtered.filter { $0.isHiDPI }
                    let standardModes = filtered.filter { !$0.isHiDPI }

                    Menu {
                        renderModeList(retinaModes, displayID: displayID, current: current)
                    } label: {
                        Label("Retina Resolutions", image: DisplayMode.iconName(hiDPI: true))
                            .labelStyle(.titleAndIcon)
                    }
                    Menu {
                        renderModeList(standardModes, displayID: displayID, current: current)
                    } label: {
                        Label("Standard Resolutions", image: DisplayMode.iconName(hiDPI: false))
                            .labelStyle(.titleAndIcon)
                    }
                } label: {
                    if let cur = current {
                        Label("\(displayTitle) (\(cur.width)×\(cur.height) @ \(Int(cur.refreshRate.rounded()))Hz)", image: cur.iconName)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text(displayTitle)
                    }
                }
            }

            Divider()

            Menu {
                if presetStore.presets.isEmpty {
                    Text("No saved presets")
                }
                ForEach(presetStore.presets) { preset in
                    Button(manager.isActive(preset) ? "✓ \(preset.displayName)" : preset.displayName) {
                        manager.apply(preset)
                    }
                    .disabled(!manager.canApply(preset))
                }

                Divider()

                Button("Save preset...") {
                    presetStore.promptToSave(using: manager)
                }
                Button("Manage presets...") {
                    openSettings(.presets)
                }
            } label: {
                Text("Presets \(Text("\(presetStore.presets.count)").bold())")
            }

            Divider()

            Button("Open System Display Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Settings...") {
                openSettings(.general)
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                // Tall enough that a display's page (including the custom emoji instructions) never scrolls.
                .frame(minWidth: 640, minHeight: 600)
                .environmentObject(manager)
                .environmentObject(settingsNavigation)
                .environmentObject(presetStore)
        }
        .defaultSize(width: 720, height: 640)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
    }

    private func openSettings(_ page: SettingsPage) {
        settingsNavigation.selection = page
        openWindow(id: "settings")
        // ScreenSmith has no Dock icon, so bring the window forward explicitly.
        NSApp.activate(ignoringOtherApps: true)
    }

    @ViewBuilder
    private func renderModeList(_ modes: [DisplayMode], displayID: CGDirectDisplayID, current: DisplayMode?) -> some View {
        if modes.isEmpty {
            Text(minimumRefreshRate > 0 ? "No resolutions at \(minimumRefreshRate)Hz or above" : "No resolutions")
        }
        ForEach(modes) { modeObj in
            Button {
                manager.setResolution(displayID: displayID, mode: modeObj.mode)
            } label: {
                let isActive = modeObj.width == current?.width &&
                               modeObj.height == current?.height &&
                               modeObj.refreshRate.rounded() == current?.refreshRate.rounded() &&
                               modeObj.isHiDPI == current?.isHiDPI

                Label(isActive ? "✓ \(modeObj.label)" : modeObj.label, image: modeObj.iconName)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

import SwiftUI
import ServiceManagement

@main
struct ScreenSmithApp: App {
    @StateObject private var manager = DisplayManager()
    @State private var startAtLogin = false
    @AppStorage("showOnlyHighRefresh") private var showOnlyHighRefresh = false
    
    @State private var renamingDisplayID: CGDirectDisplayID?
    @State private var newNameText: String = ""
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("ScreenSmith", systemImage: "display") {
            ForEach(Array(manager.displays.enumerated()), id: \.element) { index, displayID in
                let displayName = manager.getDisplayName(for: displayID)
                let current = manager.getCurrentMode(for: displayID)
                let allModes = manager.getModes(for: displayID)
                
                Menu {
                    Button("Rename...") {
                        newNameText = displayName
                        renamingDisplayID = displayID
                        openWindow(id: "rename-window")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    
                    Divider()
                    
                    if let cur = current {
                        Text("Active: \(cur.width) x \(cur.height) @ \(Int(cur.refreshRate.rounded()))Hz")
                    }
                    
                    let filtered = allModes.filter { !showOnlyHighRefresh || $0.refreshRate.rounded() >= 60.0 }
                    let retinaModes = filtered.filter { $0.isHiDPI }
                    let standardModes = filtered.filter { !$0.isHiDPI }
                    
                    Menu {
                        renderModeList(retinaModes, displayID: displayID, current: current)
                    } label: {
                        Label("Retina Resolutions", systemImage: DisplayMode.symbolName(hiDPI: true))
                    }
                    Menu {
                        renderModeList(standardModes, displayID: displayID, current: current)
                    } label: {
                        Label("Standard Resolutions", systemImage: DisplayMode.symbolName(hiDPI: false))
                    }
                } label: {
                    if let cur = current {
                        Label("\(displayName) (\(cur.width)×\(cur.height))", systemImage: cur.symbolName)
                    } else {
                        Text(displayName)
                    }
                }
            }
            
            Divider()
            
            Group {
                Toggle("Hide refresh rates below 60Hz", isOn: $showOnlyHighRefresh)
                Toggle("Start at Login", isOn: Binding(get: { startAtLogin }, set: setLoginItem))
                
                Button("Open System Display Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Divider()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        
        WindowGroup("Rename Display", id: "rename-window") {
            VStack(spacing: 20) {
                Text("Enter Custom Name")
                    .font(.headline)
                
                TextField("Name", text: $newNameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveAndClose() }
                
                HStack {
                    Button("Cancel") {
                        renamingDisplayID = nil
                        NSApp.keyWindow?.close()
                    }
                    Button("Reset") {
                        if let id = renamingDisplayID {
                            manager.resetName(for: id)
                            renamingDisplayID = nil
                            NSApp.keyWindow?.close()
                        }
                    }
                    Spacer()
                    Button("Save") { saveAndClose() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300, height: 150)
        }
        .windowResizability(.contentSize)
    }

    private func saveAndClose() {
        if let id = renamingDisplayID {
            manager.saveCustomName(newNameText, for: id)
        }
        renamingDisplayID = nil
        NSApp.keyWindow?.close()
    }

    @ViewBuilder
    private func renderModeList(_ modes: [DisplayMode], displayID: CGDirectDisplayID, current: DisplayMode?) -> some View {
        ForEach(modes) { modeObj in
            Button {
                manager.setResolution(displayID: displayID, mode: modeObj.mode)
            } label: {
                let isActive = modeObj.width == current?.width &&
                               modeObj.height == current?.height &&
                               modeObj.refreshRate.rounded() == current?.refreshRate.rounded() &&
                               modeObj.isHiDPI == current?.isHiDPI
                
                Label(isActive ? "✓ \(modeObj.label)" : modeObj.label, systemImage: modeObj.symbolName)
            }
        }
    }
    
    private func setLoginItem(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            try (enabled ? service.register() : service.unregister())
        } catch {
            NSLog("ScreenSmith: failed to update login item: \(error)")
        }
        // Show what macOS actually did, not what was requested.
        startAtLogin = service.status == .enabled
        if enabled && service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
    
    init() { _startAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled) }
}

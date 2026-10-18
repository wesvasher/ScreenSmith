import AppKit
import Combine

/// One display's resolution within a preset.
struct PresetDisplay: Codable, Identifiable, Hashable {
    /// `DisplayManager.persistentKey(for:)` of the display, so presets survive reboots and reconnects.
    let displayKey: String
    /// Name and icon when the preset was saved, shown if the display isn't connected now.
    let displayName: String
    let icon: String
    /// `DisplayMode.id` of the saved mode, used to find the same mode again.
    let modeID: String
    let width: Int
    let height: Int
    let refreshRate: Int
    let isHiDPI: Bool

    var id: String { displayKey }

    var modeDescription: String {
        "\(width) x \(height) @ \(refreshRate)Hz" + (isHiDPI ? " (Retina)" : "")
    }
}

struct Preset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var displays: [PresetDisplay]

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Preset" : trimmed
    }
}

/// Saved presets, persisted as JSON in `UserDefaults`.
final class PresetStore: ObservableObject {
    @Published var presets: [Preset] = [] {
        didSet { persist() }
    }

    private let presetsKey = "ScreenSmithPresets"

    init() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = saved
        }
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    /// Asks for a name in a standard alert that also lists what will be saved, then saves the preset.
    func promptToSave(using manager: DisplayManager) {
        let displays = manager.capturePresetDisplays()
        let alert = NSAlert()
        alert.messageText = "Save Preset"
        alert.informativeText = "Name this preset. It saves the current resolution of each attached display:\n\n"
            + displays.map { "\($0.icon) \($0.displayName): \($0.modeDescription)" }.joined(separator: "\n")
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let defaultName = "Preset \(presets.count + 1)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = defaultName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        // ScreenSmith has no Dock icon, so bring the alert forward explicitly.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        presets.append(Preset(name: name.isEmpty ? defaultName : name, displays: displays))
    }
}

extension DisplayManager {
    func capturePresetDisplays() -> [PresetDisplay] {
        displays.compactMap { displayID in
            guard let mode = getCurrentMode(for: displayID) else { return nil }
            return PresetDisplay(displayKey: persistentKey(for: displayID),
                                 displayName: getDisplayName(for: displayID),
                                 icon: icon(for: displayID),
                                 modeID: mode.id,
                                 width: mode.width,
                                 height: mode.height,
                                 refreshRate: Int(mode.refreshRate.rounded()),
                                 isHiDPI: mode.isHiDPI)
        }
    }

    func connectedDisplay(forKey key: String) -> CGDirectDisplayID? {
        displays.first { persistentKey(for: $0) == key }
    }

    /// True when at least one of the preset's displays is attached, so applying it would do something.
    func canApply(_ preset: Preset) -> Bool {
        preset.displays.contains { connectedDisplay(forKey: $0.displayKey) != nil }
    }

    /// True when every display in the preset is attached and already in its saved mode.
    func isActive(_ preset: Preset) -> Bool {
        preset.displays.allSatisfy { entry in
            guard let displayID = connectedDisplay(forKey: entry.displayKey) else { return false }
            return getCurrentMode(for: displayID)?.id == entry.modeID
        }
    }

    /// Switches each attached display in the preset to its saved mode; displays that aren't attached are skipped.
    func apply(_ preset: Preset) {
        for entry in preset.displays {
            guard let displayID = connectedDisplay(forKey: entry.displayKey),
                  getCurrentMode(for: displayID)?.id != entry.modeID,
                  let mode = getModes(for: displayID).first(where: { $0.id == entry.modeID })
            else { continue }
            setResolution(displayID: displayID, mode: mode.mode)
        }
    }
}

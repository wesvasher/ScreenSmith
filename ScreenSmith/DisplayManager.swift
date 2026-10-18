import Foundation
import CoreGraphics
import AppKit
import Combine

struct DisplayMode: Identifiable, Hashable {
    let id: String
    let mode: CGDisplayMode
    let width: Int
    let height: Int
    let refreshRate: Double
    let isHiDPI: Bool

    init(_ mode: CGDisplayMode) {
        self.mode = mode
        self.width = mode.width
        self.height = mode.height
        self.refreshRate = mode.refreshRate
        self.isHiDPI = mode.pixelWidth > mode.width
        // Built from what the menu shows, so modes that look identical share an id.
        self.id = "\(width)x\(height)@\(Int(refreshRate.rounded()))\(isHiDPI ? "-hidpi" : "")"
    }

    var sizeLabel: String { "\(width) x \(height)" }

    /// Asset-catalog icon for the mode's pixel density: a smooth shape for HiDPI, a pixelated one for standard.
    /// The catalog also has ring (density.ring.*) and solid-disc (density.circle.*) pairs to swap in.
    var iconName: String { DisplayMode.iconName(hiDPI: isHiDPI) }

    static func iconName(hiDPI: Bool) -> String {
        hiDPI ? "density.curve.hidpi" : "density.curve.standard"
    }

    var label: String {
        let roundedRate = Int(refreshRate.rounded())
        return "\(width) x \(height) @ \(roundedRate)Hz"
    }

    static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

class DisplayManager: ObservableObject {
    @Published var displays: [CGDirectDisplayID] = []
    /// Custom names keyed by `persistentKey(for:)`.
    @Published var customNames: [String: String] = [:]
    /// Sidebar emoji keyed by `persistentKey(for:)`; displays without one get a default.
    @Published var iconChoices: [String: String] = [:]
    /// Displays MonitorPanel says can be rotated; see `refreshRotationSupport()` in Rotation.swift.
    @Published var rotatableDisplays: Set<CGDirectDisplayID> = []

    private let namesKey = "ScreenSmithCustomNames"
    private let iconsKey = "ScreenSmithDisplayIcons"
    private var screenChangeObserver: AnyCancellable?

    init() {
        loadCustomNames()
        loadIconChoices()
        updateDisplayList()

        // Pick up monitors being connected, disconnected, or reconfigured.
        screenChangeObserver = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateDisplayList() }
    }

    func updateDisplayList() {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        self.displays = displayIDs
        migrateLegacyNames()
        refreshRotationSupport()
    }

    /// Display IDs can change across reboots and reconnects, so names are stored
    /// against the monitor's hardware identity instead.
    func persistentKey(for displayID: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        // Some monitors report no serial; fall back to the unit number so two identical models stay distinct.
        let suffix = serial != 0 ? "\(serial)" : "unit\(CGDisplayUnitNumber(displayID))"
        return "\(vendor)-\(model)-\(suffix)"
    }

    func getDisplayName(for displayID: CGDirectDisplayID) -> String {
        customName(for: displayID) ?? defaultName(for: displayID)
    }

    func customName(for displayID: CGDirectDisplayID) -> String? {
        customNames[persistentKey(for: displayID)]
    }

    func defaultName(for displayID: CGDirectDisplayID) -> String {
        CGDisplayIsMain(displayID) != 0 ? "Main Display" : "External Display (\(displayID))"
    }

    /// The display's sidebar emoji; built-in screens default to a laptop, others to a monitor.
    func icon(for displayID: CGDirectDisplayID) -> String {
        iconChoices[persistentKey(for: displayID)]
            ?? (CGDisplayIsBuiltin(displayID) != 0 ? DisplayIcon.laptop : DisplayIcon.desktop)
    }

    func setIcon(_ emoji: String, for displayID: CGDirectDisplayID) {
        iconChoices[persistentKey(for: displayID)] = emoji
        UserDefaults.standard.set(iconChoices, forKey: iconsKey)
    }

    private func loadIconChoices() {
        guard let saved = UserDefaults.standard.dictionary(forKey: iconsKey) as? [String: String] else { return }
        // Earlier builds stored names like "laptop" (and "custom" for an image, which is no longer supported).
        iconChoices = saved.compactMapValues { value in
            if let emoji = DisplayIcon.legacyNames[value] { return emoji }
            return value == "custom" ? nil : value
        }
    }

    func saveCustomName(_ name: String, for displayID: CGDirectDisplayID) {
        customNames[persistentKey(for: displayID)] = name
        persistNames()
    }

    func resetName(for displayID: CGDirectDisplayID) {
        customNames.removeValue(forKey: persistentKey(for: displayID))
        persistNames()
    }

    private func persistNames() {
        UserDefaults.standard.set(customNames, forKey: namesKey)
    }

    private func loadCustomNames() {
        if let saved = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] {
            self.customNames = saved
        }
    }

    /// Earlier versions keyed names by raw display ID. Move any that match a
    /// connected display over to its hardware key; leave the rest until their display shows up.
    private func migrateLegacyNames() {
        var migrated = false
        for displayID in displays {
            let legacyKey = String(displayID)
            guard let name = customNames[legacyKey] else { continue }
            customNames.removeValue(forKey: legacyKey)
            let key = persistentKey(for: displayID)
            if customNames[key] == nil { customNames[key] = name }
            migrated = true
        }
        if migrated { persistNames() }
    }

    func getCurrentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return DisplayMode(mode)
    }

    func getModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modeList = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else { return [] }
        var seen = Set<String>()
        return modeList
            .filter { $0.isUsableForDesktopGUI() }
            .map { DisplayMode($0) }
            .sorted { $0.width != $1.width ? $0.width > $1.width : $0.refreshRate.rounded() > $1.refreshRate.rounded() }
            // Drop modes that differ only in details the menu doesn't show.
            .filter { seen.insert($0.id).inserted }
    }

    func setResolution(displayID: CGDirectDisplayID, mode: CGDisplayMode) {
        if CGDisplaySetDisplayMode(displayID, mode, nil) == .success {
            updateDisplayList()
        }
    }

    /// A display mirroring another one shares its position, so it can't become main on its own.
    func isMirroring(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayMirrorsDisplay(displayID) != kCGNullDirectDisplay
    }

    /// Makes the display the main one (menu bar, and the Dock unless it's been moved) the way System Settings
    /// does: macOS treats the display at the global origin as main, so move this one to (0, 0) and shift every
    /// other display by the same amount, which keeps the arrangement unchanged.
    @discardableResult
    func makeMainDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsMain(displayID) == 0 else { return true }
        guard !isMirroring(displayID) else { return false }
        let newOrigin = CGDisplayBounds(displayID).origin

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for id in displays where !isMirroring(id) {
            let origin = CGDisplayBounds(id).origin
            CGConfigureDisplayOrigin(config, id, Int32(origin.x - newOrigin.x), Int32(origin.y - newOrigin.y))
        }
        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        updateDisplayList()
        return true
    }
}

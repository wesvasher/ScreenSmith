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

    var label: String {
        let indicator = isHiDPI ? "●" : "○"
        let roundedRate = Int(refreshRate.rounded())
        return "\(indicator) \(width) x \(height) @ \(roundedRate)Hz"
    }

    static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

class DisplayManager: ObservableObject {
    @Published var displays: [CGDirectDisplayID] = []
    /// Custom names keyed by `persistentKey(for:)`.
    @Published var customNames: [String: String] = [:]

    private let namesKey = "ScreenSmithCustomNames"
    private var screenChangeObserver: AnyCancellable?

    init() {
        loadCustomNames()
        updateDisplayList()

        // Pick up monitors being connected, disconnected, or reconfigured.
        screenChangeObserver = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateDisplayList() }
    }

    private func updateDisplayList() {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        self.displays = displayIDs
        migrateLegacyNames()
    }

    /// Display IDs can change across reboots and reconnects, so names are stored
    /// against the monitor's hardware identity instead.
    private func persistentKey(for displayID: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        // Some monitors report no serial; fall back to the unit number so two identical models stay distinct.
        let suffix = serial != 0 ? "\(serial)" : "unit\(CGDisplayUnitNumber(displayID))"
        return "\(vendor)-\(model)-\(suffix)"
    }

    func getDisplayName(for displayID: CGDirectDisplayID) -> String {
        if let custom = customNames[persistentKey(for: displayID)] { return custom }
        return CGDisplayIsMain(displayID) != 0 ? "Main Display" : "External Display (\(displayID))"
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
}

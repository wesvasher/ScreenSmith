import Foundation
import CoreGraphics
import AppKit
import Combine

struct DisplayMode: Identifiable, Hashable {
    let id = UUID()
    let mode: CGDisplayMode
    let width: Int
    let height: Int
    let refreshRate: Double
    let isHiDPI: Bool
    
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
    @Published var customNames: [CGDirectDisplayID: String] = [:]
    
    private let namesKey = "ScreenSmithCustomNames"
    
    init() {
        loadCustomNames()
        updateDisplayList()
    }
    
    private func updateDisplayList() {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        self.displays = displayIDs
    }
    
    func getDisplayName(for displayID: CGDirectDisplayID) -> String {
        if let custom = customNames[displayID] { return custom }
        return CGDisplayIsMain(displayID) != 0 ? "Main Display" : "External Display (\(displayID))"
    }
    
    func saveCustomName(_ name: String, for displayID: CGDirectDisplayID) {
        customNames[displayID] = name
        persistNames()
        objectWillChange.send()
    }
    
    func resetName(for displayID: CGDirectDisplayID) {
        customNames.removeValue(forKey: displayID)
        persistNames()
        objectWillChange.send()
    }
    
    private func persistNames() {
        let stringKeyDict = Dictionary(uniqueKeysWithValues: customNames.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stringKeyDict, forKey: namesKey)
    }
    
    private func loadCustomNames() {
        if let saved = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] {
            self.customNames = Dictionary(uniqueKeysWithValues: saved.compactMap { (key, value) in
                guard let id = UInt32(key) else { return nil }
                return (id, value)
            })
        }
    }

    func getCurrentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return DisplayMode(mode: mode, width: mode.width, height: mode.height, refreshRate: mode.refreshRate, isHiDPI: mode.pixelWidth > mode.width)
    }
    
    func getModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modeList = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else { return [] }
        return modeList.map { DisplayMode(mode: $0, width: $0.width, height: $0.height, refreshRate: $0.refreshRate, isHiDPI: $0.pixelWidth > $0.width) }
            .sorted { $0.width != $1.width ? $0.width > $1.width : $0.refreshRate.rounded() > $1.refreshRate.rounded() }
    }
    
    func setResolution(displayID: CGDirectDisplayID, mode: CGDisplayMode) {
        if CGDisplaySetDisplayMode(displayID, mode, nil) == .success {
            updateDisplayList()
        }
    }
}

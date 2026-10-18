import AppKit

/// A display's sidebar icon is a single emoji: one of the built-ins below, or any emoji picked in Settings.
enum DisplayIcon {
    static let laptop = "💻"
    static let desktop = "🖥️"
    static let tv = "📺"
    static let builtIns = [laptop, desktop, tv]
    /// What the fourth, customizable choice shows until the user picks another emoji.
    static let defaultCustom = "😀"

    /// Names that earlier builds stored instead of emoji.
    static let legacyNames = ["laptop": laptop, "desktop": desktop, "tv": tv]

    static func title(for emoji: String) -> String {
        switch emoji {
        case laptop: "Laptop"
        case desktop: "Monitor"
        case tv: "TV"
        default: "Custom emoji"
        }
    }
}

extension Character {
    /// True for characters that render as emoji, but not plain digits or symbols like "#" that are only emoji-capable.
    var isEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || (unicodeScalars.count > 1 && unicodeScalars.contains { $0.properties.isEmoji })
    }
}

/// The "Hide refresh rates below" setting: modes under the cutoff are left out of the menu. 0 means off.
enum RefreshFilter {
    static let key = "minimumRefreshRate"

    /// Standard rates found on Macs and monitors of roughly the last decade.
    static let rates = [24, 25, 30, 48, 50, 60, 72, 75, 85, 90, 100, 120, 144, 165, 170, 175, 180, 200, 240, 280, 360, 480, 500, 540]

    /// Earlier builds had an on/off "Hide refresh rates below 60Hz" setting; carry it over as a 60Hz cutoff.
    static func migrateLegacySetting() {
        let defaults = UserDefaults.standard
        let legacyKey = "showOnlyHighRefresh"
        guard defaults.object(forKey: legacyKey) != nil else { return }
        if defaults.object(forKey: key) == nil, defaults.bool(forKey: legacyKey) {
            defaults.set(60, forKey: key)
        }
        defaults.removeObject(forKey: legacyKey)
    }
}

struct DisplayDetailRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

extension DisplayManager {
    /// Read-only facts shown in the Details section of a display's settings page.
    func details(for displayID: CGDirectDisplayID) -> [DisplayDetailRow] {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
        let current = getCurrentMode(for: displayID)
        let millimetres = CGDisplayScreenSize(displayID)
        let inches = hypot(millimetres.width, millimetres.height) / 25.4
        let maxRefresh = getModes(for: displayID).map { Int($0.refreshRate.rounded()) }.max()
        let serial = CGDisplaySerialNumber(displayID)
        let hdr = (screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1

        return [
            DisplayDetailRow(label: "Model", value: screen?.localizedName ?? "Unknown"),
            DisplayDetailRow(label: "Current Mode", value: current?.label ?? "Unknown"),
            DisplayDetailRow(label: "HiDPI", value: current.map { $0.isHiDPI ? "Retina" : "Standard" } ?? "Unknown"),
            DisplayDetailRow(label: "Size", value: inches > 0 ? String(format: "%.1f-inch", inches) : "Unknown"),
            DisplayDetailRow(label: "Max Refresh", value: maxRefresh.map { "\($0)Hz" } ?? "Unknown"),
            DisplayDetailRow(label: "HDR Supported", value: hdr ? "Yes" : "No"),
            DisplayDetailRow(label: "Serial Number", value: serial != 0 ? String(serial) : "Not reported"),
        ]
    }
}

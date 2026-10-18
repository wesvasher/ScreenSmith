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

struct PixelSize: Equatable {
    let width: Int
    let height: Int

    var label: String { "\(width) x \(height)" }
}

extension DisplayMode {
    var pixelSize: PixelSize { PixelSize(width: mode.pixelWidth, height: mode.pixelHeight) }

    /// Menu text, calling out modes that map the panel's pixels exactly: 1:1, or 2x for Retina.
    func menuLabel(nativeSize: PixelSize?) -> String {
        guard pixelSize == nativeSize else { return label }
        return label + (isHiDPI ? " · Native (2×)" : " · Native")
    }

    /// Whether the mode has the given height/width shape; the tolerance covers rounding in odd sizes like 1312x848.
    func hasAspect(_ aspect: Double) -> Bool {
        abs(Double(height) / Double(width) - aspect) < 0.005
    }
}

extension DisplayManager {
    /// kDisplayModeNativeFlag from IOGraphicsTypes.h, set on modes whose backing pixels are the panel's own.
    private static let nativeModeFlag: UInt32 = 0x0200_0000

    /// The panel's physical resolution. Not the largest mode: macOS also offers supersampled modes
    /// (e.g. 6720x3780 on a 3840x2160 panel) that are rendered larger and scaled down.
    func nativePixelSize(for displayID: CGDirectDisplayID) -> PixelSize? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        guard let native = modes.first(where: { $0.ioFlags & Self.nativeModeFlag != 0 }) else { return nil }
        return PixelSize(width: native.pixelWidth, height: native.pixelHeight)
    }

    /// For a notched built-in panel, the panel's native height/width shape. Modes with this shape fill the
    /// whole panel around the notch; the rest (16:10) are letterboxed below it. Nil for displays without a notch.
    func notchPanelAspect(for displayID: CGDirectDisplayID) -> Double? {
        guard CGDisplayIsBuiltin(displayID) != 0 else { return nil }
        let modes = getModes(for: displayID)
        let native = nativePixelSize(for: displayID)
            ?? modes.map(\.pixelSize).max { $0.width * $0.height < $1.width * $1.height }
        guard let native else { return nil }
        let aspect = Double(native.height) / Double(native.width)
        // Panels without a notch have every mode in the native shape, so there's nothing to split.
        return modes.contains { !$0.hasAspect(aspect) } ? aspect : nil
    }

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

        var rows = [
            DisplayDetailRow(label: "Model", value: screen?.localizedName ?? "Unknown"),
            DisplayDetailRow(label: "Current Mode", value: current?.label ?? "Unknown"),
            DisplayDetailRow(label: "Native Resolution", value: nativePixelSize(for: displayID)?.label ?? "Unknown"),
            DisplayDetailRow(label: "HiDPI", value: current.map { $0.isHiDPI ? "Retina" : "Standard" } ?? "Unknown"),
        ]
        if let notchAspect = notchPanelAspect(for: displayID), let current {
            rows.append(DisplayDetailRow(label: "Notch",
                                         value: current.hasAspect(notchAspect) ? "Full panel (notch)" : "Below notch (no notch)"))
        }
        return rows + [
            DisplayDetailRow(label: "Size", value: inches > 0 ? String(format: "%.1f-inch", inches) : "Unknown"),
            DisplayDetailRow(label: "Max Refresh", value: maxRefresh.map { "\($0)Hz" } ?? "Unknown"),
            DisplayDetailRow(label: "HDR Supported", value: hdr ? "Yes" : "No"),
            DisplayDetailRow(label: "Serial Number", value: serial != 0 ? String(serial) : "Not reported"),
        ]
    }
}

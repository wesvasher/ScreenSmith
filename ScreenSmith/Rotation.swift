import AppKit
import ObjectiveC

/// Display rotation choices, labelled like System Settings › Displays › Rotation.
enum DisplayRotation {
    static let options = [0, 90, 180, 270]

    static func title(for degrees: Int) -> String {
        degrees == 0 ? "Standard" : "\(degrees)°"
    }
}

/// macOS has no public API for rotating a display. System Settings uses `MPDisplay` from the private
/// MonitorPanel framework, so ScreenSmith does too, through the Objective-C runtime. If the framework,
/// class or methods ever go away, `canRotate` returns false and the rotation controls are hidden.
private enum MonitorPanel {
    private static let isLoaded =
        dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY) != nil
    private static let setOrientation = NSSelectorFromString("setOrientation:")

    /// One shared `MPDisplayMgr`, like System Settings keeps. Creating one is expensive, so it must never
    /// happen while the menu is being built; `reset()` drops it when displays change and the next use rebuilds it.
    private static var sharedManager: NSObject?

    static func reset() {
        sharedManager = nil
    }

    /// The `MPDisplay` for a display. Its `displayID` is the same number as the CGDirectDisplayID.
    static func display(for displayID: CGDirectDisplayID) -> NSObject? {
        guard isLoaded, let managerClass = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return nil }
        let manager = sharedManager ?? managerClass.init()
        sharedManager = manager
        guard manager.responds(to: NSSelectorFromString("displays")),
              let displays = manager.value(forKey: "displays") as? [NSObject]
        else { return nil }
        return displays.first { display in
            display.responds(to: NSSelectorFromString("displayID"))
                && (display.value(forKey: "displayID") as? NSNumber)?.uint32Value == displayID
        }
    }

    static func canRotate(_ displayID: CGDirectDisplayID) -> Bool {
        guard let display = display(for: displayID),
              display.responds(to: setOrientation),
              display.responds(to: NSSelectorFromString("canChangeOrientation"))
        else { return false }
        return (display.value(forKey: "canChangeOrientation") as? NSNumber)?.boolValue ?? false
    }

    static func setRotation(_ degrees: Int, for displayID: CGDirectDisplayID) -> Bool {
        guard let display = display(for: displayID), display.responds(to: setOrientation) else { return false }
        // -[MPDisplay setOrientation:(int)degrees]; an int argument can't go through perform(_:with:).
        typealias SetOrientation = @convention(c) (AnyObject, Selector, Int32) -> Void
        let implementation = unsafeBitCast(display.method(for: setOrientation), to: SetOrientation.self)
        implementation(display, setOrientation, Int32(degrees))
        return true
    }
}

extension DisplayManager {
    /// The display's current rotation in degrees (0, 90, 180 or 270), from the public CGDisplayRotation.
    func rotation(for displayID: CGDirectDisplayID) -> Int {
        Int(CGDisplayRotation(displayID).rounded()) % 360
    }

    /// Cached by `refreshRotationSupport()`, so menus and views never query MonitorPanel while building.
    func canRotate(_ displayID: CGDirectDisplayID) -> Bool {
        rotatableDisplays.contains(displayID)
    }

    /// Called whenever the display list changes; rebuilds the MonitorPanel view of the displays.
    func refreshRotationSupport() {
        MonitorPanel.reset()
        let rotatable = Set(displays.filter { MonitorPanel.canRotate($0) })
        if rotatable != rotatableDisplays { rotatableDisplays = rotatable }
    }

    @discardableResult
    func setRotation(_ degrees: Int, for displayID: CGDirectDisplayID) -> Bool {
        guard rotation(for: displayID) != degrees else { return true }
        guard MonitorPanel.setRotation(degrees, for: displayID) else { return false }
        updateDisplayList()
        return true
    }
}

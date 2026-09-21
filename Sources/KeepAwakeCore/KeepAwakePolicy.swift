import Foundation
import IOKit
import IOKit.ps

public enum KeepAwakePolicy {
    /// Zero is the wire value for an explicitly selected session with no timer.
    public static let noTimer: TimeInterval = 0
    public static let maximumDuration: TimeInterval = 12 * 60 * 60
    public static let batteryFloor = 15

    public static func validDuration(_ seconds: TimeInterval) -> Bool {
        seconds == noTimer || (seconds.isFinite && seconds >= 60 && seconds <= maximumDuration)
    }

    public static func stopReason(
        now: Date, deadline: Date?, elapsed: TimeInterval, duration: TimeInterval,
        connected: Bool, batteryPercent: Int?
    ) -> String? {
        if !connected { return "closed" }
        if duration != noTimer, (deadline.map { now >= $0 } ?? false) || elapsed >= duration { return "expired" }
        if let batteryPercent, batteryPercent <= batteryFloor { return "battery" }
        return nil
    }
}

public enum KeepAwakePower {
    public static func lidClosed() -> Bool? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistryEntryCreateCFProperty(entry, "AppleClamshellState" as CFString, nil, 0)?
            .takeRetainedValue() as? Bool
    }

    /// The same kernel property controlled by Apple's `pmset disablesleep`.
    public static func sleepDisabled() -> Bool? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistryEntryCreateCFProperty(entry, "SleepDisabled" as CFString, nil, 0)?
            .takeRetainedValue() as? Bool
    }

    /// nil means on external power, no battery, or unavailable battery data.
    public static func dischargingBatteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return capacity * 100 / maximum
        }
        return nil
    }
}

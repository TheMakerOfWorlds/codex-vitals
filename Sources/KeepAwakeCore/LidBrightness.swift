import CoreGraphics
import Darwin
import Foundation

public struct BuiltInBrightness: Equatable {
    public let displayID: UInt32
    public let level: Float

    public init(displayID: UInt32, level: Float) {
        self.displayID = displayID
        self.level = level
    }
}

public protocol BuiltInDisplayBrightness {
    func read() -> BuiltInBrightness?
    func set(_ brightness: BuiltInBrightness) -> Bool
}

/// Owns one saved brightness for each lid-close cycle. Polls never replace it with zero.
public final class LidBrightnessSession {
    private let display: BuiltInDisplayBrightness
    private var lastOpenBrightness: BuiltInBrightness?
    private var savedBrightness: BuiltInBrightness?

    public init(display: BuiltInDisplayBrightness) { self.display = display }

    public func update(lidClosed: Bool?) {
        guard let lidClosed else { return }
        if !lidClosed {
            guard restore() else { return }
            lastOpenBrightness = valid(display.read())
            return
        }

        let current = valid(display.read())
        if savedBrightness == nil {
            // macOS can darken the panel before reporting the closed lid. Preserve
            // our last open-lid reading in that case, including an intentional zero.
            if let current, current.level > 0 {
                savedBrightness = current
            } else {
                savedBrightness = lastOpenBrightness ?? current
            }
        }
        guard let saved = savedBrightness else { return }
        // Auto-brightness or another utility can raise the backlight while closed.
        // Retry failed writes without ever replacing the original saved value.
        if current?.displayID != saved.displayID || current?.level != 0 {
            _ = display.set(BuiltInBrightness(displayID: saved.displayID, level: 0))
        }
    }

    @discardableResult
    public func restore() -> Bool {
        guard let saved = savedBrightness else { return true }
        guard display.set(saved) else { return false }
        savedBrightness = nil
        lastOpenBrightness = nil
        return true
    }

    private func valid(_ value: BuiltInBrightness?) -> BuiltInBrightness? {
        guard let value, value.level.isFinite, (0...1).contains(value.level) else { return nil }
        return value
    }
}

/// DisplayServices controls the actual backlight on both Intel and Apple Silicon.
/// Resolve its private API at runtime so unsupported macOS versions safely do nothing.
public final class SystemBuiltInDisplayBrightness: BuiltInDisplayBrightness {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private let library: UnsafeMutableRawPointer?
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
        library = handle
        getBrightness = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
            .map { unsafeBitCast($0, to: GetBrightness.self) }
        setBrightness = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
            .map { unsafeBitCast($0, to: SetBrightness.self) }
    }

    deinit { if let library { dlclose(library) } }

    public func read() -> BuiltInBrightness? {
        guard let getBrightness, setBrightness != nil else { return nil }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        for id in displays.prefix(Int(count)) where CGDisplayIsBuiltin(id) != 0 {
            var level: Float = 0
            if getBrightness(id, &level) == 0, level.isFinite, (0...1).contains(level) {
                return BuiltInBrightness(displayID: id, level: level)
            }
        }
        return nil
    }

    public func set(_ brightness: BuiltInBrightness) -> Bool {
        // Never fall back to the main screen: it can be an external monitor.
        guard CGDisplayIsBuiltin(brightness.displayID) != 0,
              brightness.level.isFinite, (0...1).contains(brightness.level),
              let setBrightness, let getBrightness,
              setBrightness(brightness.displayID, brightness.level) == 0 else { return false }
        var actual: Float = -1
        return getBrightness(brightness.displayID, &actual) == 0
            && actual.isFinite && abs(actual - brightness.level) < 0.01
    }
}

import Foundation

public protocol KeepAwakeSessionEnvironment {
    var now: Date { get }
    var uptime: TimeInterval { get }
    var interrupted: Bool { get }
    var batteryPercent: Int? { get }
    var sleepDisabled: Bool? { get }
    func setSleepDisabled(_ disabled: Bool) -> Bool
    func waitForStop() -> String?
    func send(_ message: String)
    func waitBeforeRetry()
    func updateDisplayBrightness()
    func restoreDisplayBrightness() -> Bool
}

/// The privileged session's complete lifecycle, independently testable without changing power settings.
public enum KeepAwakeSession {
    public static func run(duration: TimeInterval, environment: KeepAwakeSessionEnvironment) {
        guard KeepAwakePolicy.validDuration(duration) else { environment.send("ERROR duration"); return }
        guard let disabled = environment.sleepDisabled else { environment.send("ERROR unsupported"); return }
        guard !disabled else { environment.send("ERROR busy"); return }
        if let battery = environment.batteryPercent, battery <= KeepAwakePolicy.batteryFloor {
            environment.send("ERROR battery"); return
        }
        guard !environment.interrupted else { environment.send("STOPPED stopped"); return }

        let started = environment.uptime
        let deadline = duration == KeepAwakePolicy.noTimer ? nil : environment.now.addingTimeInterval(duration)
        let enabled = environment.setSleepDisabled(true)
        var reason = enabled ? "stopped" : "failed"
        if enabled {
            environment.updateDisplayBrightness()
            environment.send(deadline.map { "ACTIVE \($0.timeIntervalSince1970)" } ?? "ACTIVE never")
            while !environment.interrupted {
                if let stop = KeepAwakePolicy.stopReason(
                    now: environment.now, deadline: deadline,
                    elapsed: environment.uptime - started, duration: duration,
                    connected: true, batteryPercent: environment.batteryPercent
                ) { reason = stop; break }
                if environment.sleepDisabled != true { reason = "changed"; break }
                environment.updateDisplayBrightness()
                if let stop = environment.waitForStop() { reason = stop; break }
            }
        }

        // Restore before allowing lid sleep, while the panel is still addressable.
        // Display failures must never prevent the more important sleep cleanup.
        for attempt in 0..<3 {
            if environment.restoreDisplayBrightness() { break }
            if attempt == 2 { environment.send("NOTICE brightness-restore") }
            else { environment.waitBeforeRetry() }
        }

        // Even a failed enable can have applied the setting. Always verify restoration.
        // Never announce "off" while powerd has not confirmed the cleanup.
        var attempts = 0
        while !environment.setSleepDisabled(false) {
            attempts += 1
            if attempts == 3 { environment.send("ERROR restoring") }
            environment.waitBeforeRetry()
        }
        environment.send(enabled ? "STOPPED \(reason)" : "ERROR enable")
    }
}

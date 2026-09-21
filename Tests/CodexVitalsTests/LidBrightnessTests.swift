import KeepAwakeCore
import XCTest

final class LidBrightnessTests: XCTestCase {
    func testLidCloseDimsAndRepeatedPollsPreserveOriginalBrightness() {
        let display = FakeBuiltInDisplay(level: 0.73)
        let session = LidBrightnessSession(display: display)
        session.update(lidClosed: false)
        XCTAssertTrue(display.writes.isEmpty)
        session.update(lidClosed: true)
        session.update(lidClosed: true)
        session.update(lidClosed: true)
        XCTAssertEqual(display.writes.map(\.level), [0])
        session.update(lidClosed: false)
        XCTAssertEqual(display.writes.map(\.level), [0, 0.73])
        XCTAssertEqual(display.level, 0.73)
    }

    func testEachLidCycleRestoresTheLatestUserBrightness() {
        let display = FakeBuiltInDisplay(level: 0.8)
        let session = LidBrightnessSession(display: display)
        session.update(lidClosed: true)
        session.update(lidClosed: false)
        display.level = 0.4
        session.update(lidClosed: false)
        session.update(lidClosed: true)
        session.update(lidClosed: false)
        XCTAssertEqual(display.writes.map(\.level), [0, 0.8, 0, 0.4])
    }

    func testSystemDimmingAtLidCloseDoesNotErasePreviousLevel() {
        let display = FakeBuiltInDisplay(level: 0.6)
        let session = LidBrightnessSession(display: display)
        session.update(lidClosed: false)
        display.level = 0
        session.update(lidClosed: true)
        session.update(lidClosed: false)
        XCTAssertEqual(display.level, 0.6)
    }

    func testAutoBrightnessWhileClosedDoesNotReplaceSavedLevel() {
        let display = FakeBuiltInDisplay(level: 0.65)
        let session = LidBrightnessSession(display: display)
        session.update(lidClosed: true)
        display.level = 0.2
        session.update(lidClosed: true)
        XCTAssertEqual(display.level, 0)
        session.update(lidClosed: false)
        XCTAssertEqual(display.level, 0.65)
    }

    func testUnknownLidOrUnavailableDisplayNeverChangesBrightness() {
        let display = FakeBuiltInDisplay(level: 0.5)
        let session = LidBrightnessSession(display: display)
        session.update(lidClosed: nil)
        display.readable = false
        session.update(lidClosed: true)
        XCTAssertTrue(session.restore())
        XCTAssertTrue(display.writes.isEmpty)
    }

    func testFailedReadWhileClosedKeepsTheSavedBrightness() {
        let display = FakeBuiltInDisplay(level: 0.7)
        let session = LidBrightnessSession(display: display)
        session.update(lidClosed: false)
        display.readable = false
        session.update(lidClosed: true)
        XCTAssertEqual(display.level, 0)
        display.readable = true
        session.update(lidClosed: false)
        XCTAssertEqual(display.level, 0.7)
    }

    func testFailedDimThatActuallyChangedBrightnessStillRestores() {
        let display = FakeBuiltInDisplay(level: 0.9)
        let session = LidBrightnessSession(display: display)
        display.success = false
        session.update(lidClosed: true)
        XCTAssertEqual(display.level, 0)
        display.success = true
        XCTAssertTrue(session.restore())
        XCTAssertEqual(display.level, 0.9)
    }

    func testFailedRestoreRetriesWithoutForgettingOriginalLevel() {
        let display = FakeBuiltInDisplay(level: 0.9)
        let session = LidBrightnessSession(display: display)
        session.update(lidClosed: true)
        display.success = false
        session.update(lidClosed: false)
        session.update(lidClosed: false)
        display.success = true
        session.update(lidClosed: false)
        XCTAssertEqual(display.writes.map(\.level), [0, 0.9, 0.9, 0.9])
        XCTAssertTrue(session.restore())
        XCTAssertEqual(display.writes.count, 4)
    }

    func testStartingClosedAndZeroBrightnessAreHandledWithoutBrightening() {
        for initial: Float in [0, 0.3] {
            let display = FakeBuiltInDisplay(level: initial)
            let session = LidBrightnessSession(display: display)
            session.update(lidClosed: true)
            XCTAssertEqual(display.level, 0)
            XCTAssertTrue(session.restore())
            XCTAssertEqual(display.level, initial)
        }
    }

    func testInvalidBrightnessIsNeverSavedOrWritten() {
        for level: Float in [-0.1, 1.1, .nan, .infinity] {
            let display = FakeBuiltInDisplay(level: level)
            let session = LidBrightnessSession(display: display)
            session.update(lidClosed: false)
            session.update(lidClosed: true)
            XCTAssertTrue(session.restore())
            XCTAssertTrue(display.writes.isEmpty)
        }
    }
}

private final class FakeBuiltInDisplay: BuiltInDisplayBrightness {
    var level: Float
    var readable = true
    var success = true
    var writes: [BuiltInBrightness] = []
    init(level: Float) { self.level = level }
    func read() -> BuiltInBrightness? { readable ? BuiltInBrightness(displayID: 42, level: level) : nil }
    func set(_ brightness: BuiltInBrightness) -> Bool {
        XCTAssertEqual(brightness.displayID, 42)
        writes.append(brightness)
        level = brightness.level
        return success
    }
}

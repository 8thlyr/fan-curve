import Testing
import Foundation
import FanCurveCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Swift Testing port of the assertions in Sources/FanCurveCheck/main.swift.
// The check executable stays in place for CI and the release workflow; these
// tests cover the same behaviours so `swift test` runs them as well.
//
// `#expect`/`#require` expand into a closure that captures its arguments
// immutably, so calls to `mutating` state machines are evaluated into a local
// first and the local is handed to the expectation.

@Suite("Fan curve")
struct FanCurveTests {
    private let curve = FanCurve(points: [
        CurvePoint(temperature: 40, percentage: 10),
        CurvePoint(temperature: 60, percentage: 50),
        CurvePoint(temperature: 80, percentage: 90)
    ])

    /// Interpolates between points, clamps outside the first and last point, and
    /// rejects descending percentages, too-narrow gaps, and too few points.
    @Test func interpolationValidityAndClamping() {
        #expect(curve.percentage(at: 20) == 10)
        #expect(curve.percentage(at: 50) == 30)
        #expect(curve.percentage(at: 100) == 90)

        #expect(FanCurve.isValid(FanCurve.defaultPoints))
        #expect(!FanCurve.isValid([
            CurvePoint(temperature: 40, percentage: 80),
            CurvePoint(temperature: 60, percentage: 20)
        ]))
        #expect(!FanCurve.isValid([
            CurvePoint(temperature: 40, percentage: 20),
            CurvePoint(temperature: 41, percentage: 30)
        ]))
        #expect(!FanCurve.isValid([CurvePoint(temperature: 40, percentage: 20)]))
    }

    /// Inserts a point in the widest gap, refuses narrow gaps and the last
    /// point, and refuses to delete below the minimum point count.
    @Test func addingAndDeletingPoints() throws {
        let added = try #require(FanCurve.addingPoint(to: [
            CurvePoint(temperature: 40, percentage: 20),
            CurvePoint(temperature: 60, percentage: 40),
            CurvePoint(temperature: 90, percentage: 100)
        ]))
        #expect(added == [
            CurvePoint(temperature: 40, percentage: 20),
            CurvePoint(temperature: 60, percentage: 40),
            CurvePoint(temperature: 75, percentage: 70),
            CurvePoint(temperature: 90, percentage: 100)
        ])
        #expect(FanCurve.deletingPoint(at: 2, from: added) == [
            CurvePoint(temperature: 40, percentage: 20),
            CurvePoint(temperature: 60, percentage: 40),
            CurvePoint(temperature: 90, percentage: 100)
        ])
        #expect(FanCurve.deletingPoint(at: 0, from: Array(added.prefix(2))) == nil)
        #expect(FanCurve.addingPoint(to: [
            CurvePoint(temperature: 40, percentage: 20),
            CurvePoint(temperature: 42, percentage: 40)
        ]) == nil)
        // The midpoint percentage is rounded, and fractional temperatures survive.
        #expect(FanCurve.addingPoint(to: [
            CurvePoint(temperature: 30.1, percentage: 20),
            CurvePoint(temperature: 34.1, percentage: 40)
        ]) == [
            CurvePoint(temperature: 30.1, percentage: 20),
            CurvePoint(temperature: 32.1, percentage: 30),
            CurvePoint(temperature: 34.1, percentage: 40)
        ])
    }

    /// Stored curve data is size-limited and re-validated after decoding.
    @Test func pointDecodingLimits() throws {
        let sharedCurve = [
            CurvePoint(temperature: 40, percentage: 10),
            CurvePoint(temperature: 60, percentage: 50)
        ]
        #expect(FanCurve.decodePoints(from: try JSONEncoder().encode(sharedCurve)) == sharedCurve)
        #expect(FanCurve.decodePoints(from: Data("not json".utf8)) == nil)
        #expect(FanCurve.decodePoints(from: Data(repeating: 0, count: 16_385)) == nil)
        #expect(FanCurve.decodePoints(from: try JSONEncoder().encode([
            CurvePoint(temperature: 40, percentage: 80),
            CurvePoint(temperature: 60, percentage: 20)
        ])) == nil)
    }
}

@Suite("Fan hardware rules")
struct FanHardwareTests {
    /// Fan RPM is interpolated and clamped to the fan's own range; automatic
    /// scene selection follows the power source, while manual selection never
    /// changes the profile.
    @Test func rpmMappingAndSceneSelection() {
        let fan = FanRange(id: 0, minimumRPM: 2_000, maximumRPM: 8_000)
        #expect(fan.rpm(at: -1) == 2_000)
        #expect(fan.rpm(at: 50) == 5_000)
        #expect(fan.rpm(at: 101) == 8_000)

        #expect(FanSceneCatalog.names == ["Balanced", "Quiet", "Cooling"])
        #expect(SceneSelection.profile(for: .battery, automatic: true) == FanSceneCatalog.batteryProfile)
        #expect(SceneSelection.profile(for: .external, automatic: true) == FanSceneCatalog.externalPowerProfile)
        #expect(SceneSelection.profile(for: .ups, automatic: true) == FanSceneCatalog.externalPowerProfile)
        #expect(SceneSelection.profile(for: .unknown, automatic: true) == FanSceneCatalog.externalPowerProfile)
        #expect(SceneSelection.profile(for: .battery, automatic: false) == nil)
        #expect(SceneSelection.changesProfile(
            currentProfile: FanSceneCatalog.externalPowerProfile,
            for: .battery,
            automatic: true
        ))
        #expect(!SceneSelection.changesProfile(
            currentProfile: FanSceneCatalog.externalPowerProfile,
            for: .unknown,
            automatic: true
        ))
    }

    /// Ceilings and cooling priority clamp on init, caps report when they bite,
    /// and stored data with missing keys falls back to the defaults.
    @Test func budgetsAndCaps() throws {
        let disabledBudget = FanBudget.disabled
        #expect(disabledBudget.applying(to: 80) == 80)
        #expect(!disabledBudget.caps(80))

        let cappedBudget = FanBudget(enabled: true, ceilingPercentage: 40, coolingPriority: 0)
        #expect(cappedBudget.applying(to: 80) == 40)
        #expect(cappedBudget.caps(80))

        let boostedBudget = FanBudget(enabled: true, ceilingPercentage: 100, coolingPriority: 100)
        #expect(boostedBudget.applying(to: 40) == 100)

        #expect(
            FanBudget(enabled: true, ceilingPercentage: -1, coolingPriority: 101)
                == FanBudget(enabled: true, ceilingPercentage: 0, coolingPriority: 100)
        )

        let partialBudget = try JSONDecoder().decode(
            FanBudget.self,
            from: Data(#"{"enabled":true}"#.utf8)
        )
        #expect(partialBudget == FanBudget(enabled: true))
    }

    /// Acceleration is chosen by temperature rate, and each smoothing step
    /// respects the deadband and the rise/fall limits.
    @Test func smoothing() {
        #expect(FanSmoothing.acceleration(forTemperatureRate: nil) == .none)
        #expect(FanSmoothing.acceleration(forTemperatureRate: 1.49) == .none)
        #expect(FanSmoothing.acceleration(forTemperatureRate: 1.5) == .rise)
        #expect(FanSmoothing.acceleration(forTemperatureRate: -1.5) == .fall)
        #expect(FanSmoothing.acceleration(forTemperatureRate: .nan) == .none)

        #expect(FanSmoothing.next(current: 20, target: 80) == 22)
        #expect(FanSmoothing.next(current: 80, target: 20) == 79)
        #expect(FanSmoothing.next(current: 50, target: 53) == 52)
        #expect(FanSmoothing.next(current: 50, target: 52) == 51)
        #expect(FanSmoothing.next(current: 20, target: 80, acceleration: .rise) == 28)
        #expect(FanSmoothing.next(current: 80, target: 20, acceleration: .fall) == 76)
        #expect(FanSmoothing.next(current: 20, target: 80, advance: false) == 20)

        var settledRise = 40
        for _ in 0..<40 {
            settledRise = FanSmoothing.next(current: settledRise, target: 100)
        }
        #expect(settledRise == 100)
    }

    /// The resolver applies the budget, smooths towards it, and drops straight
    /// to a lower scene ceiling instead of stepping down.
    @Test func outputResolution() {
        let cappedBudget = FanBudget(enabled: true, ceilingPercentage: 40, coolingPriority: 0)

        // A budget cap applies even while control is disabled.
        #expect(FanOutputResolver.resolve(
            curvePercentage: 80,
            currentPercentage: 20,
            isEnabled: false,
            budget: cappedBudget,
            advanceSmoothing: false
        ) == FanOutputResolution(percentage: 40, targetPercentage: 40, budgetCapped: true))

        #expect(FanOutputResolver.resolve(
            curvePercentage: 80,
            currentPercentage: 20,
            isEnabled: true,
            budget: .disabled,
            advanceSmoothing: true
        ) == FanOutputResolution(percentage: 22, targetPercentage: 80, budgetCapped: false))

        // A fast temperature rise or fall uses the accelerated step.
        #expect(FanOutputResolver.resolve(
            curvePercentage: 80,
            currentPercentage: 20,
            isEnabled: true,
            budget: .disabled,
            advanceSmoothing: true,
            temperatureRate: 2
        ) == FanOutputResolution(percentage: 28, targetPercentage: 80, budgetCapped: false))

        #expect(FanOutputResolver.resolve(
            curvePercentage: 20,
            currentPercentage: 80,
            isEnabled: true,
            budget: .disabled,
            advanceSmoothing: true,
            temperatureRate: -2
        ) == FanOutputResolution(percentage: 76, targetPercentage: 20, budgetCapped: false))

        #expect(FanOutputResolver.resolve(
            curvePercentage: 80,
            currentPercentage: 80,
            isEnabled: true,
            budget: cappedBudget,
            advanceSmoothing: true
        ) == FanOutputResolution(percentage: 40, targetPercentage: 40, budgetCapped: true))

        #expect(FanOutputResolver.resolve(
            curvePercentage: 20,
            currentPercentage: 80,
            isEnabled: true,
            budget: .disabled,
            advanceSmoothing: true
        ) == FanOutputResolution(percentage: 79, targetPercentage: 20, budgetCapped: false))
    }

    /// Averages the CPU sensor keys for this architecture, falls back to the
    /// Intel keys, and ignores non-finite, zero, and out-of-range readings.
    @Test func cpuTemperatureAveraging() {
        let temperatures = [
            "Tp01": 60.0,
            "Tf04": 80.0,
            "Tg0U": 100.0,
            "TC0D": 50.0,
            "TC3C": 70.0
        ]
        #if arch(arm64)
        let temperatureSnapshot = MacHardware.cpuTemperatureSnapshot(
            availableKeys: Set(temperatures.keys),
            read: { temperatures[$0] }
        )
        #expect(temperatureSnapshot?.average == 70)
        #expect(temperatureSnapshot?.sensorKeys == ["Tf04", "Tp01"])
        #else
        let temperatureSnapshot = MacHardware.cpuTemperatureSnapshot(
            availableKeys: Set(temperatures.keys),
            read: { temperatures[$0] }
        )
        #expect(temperatureSnapshot?.average == 70)
        #expect(temperatureSnapshot?.sensorKeys == ["TC3C"])
        #endif

        #if arch(x86_64)
        let intelFallbackTemperatures = ["TCAD": 65.0, "TC0D": 55.0]
        #expect(MacHardware.averageCPUTemperature(
            availableKeys: Set(intelFallbackTemperatures.keys),
            read: { intelFallbackTemperatures[$0] }
        ) == 65)
        #endif

        let invalidTemperatures = [
            "Tp01": Double.nan,
            "Tp05": 111.0,
            "Tf04": 0.0,
            "TCAD": 0.0,
            "TC0D": Double.nan,
            "TC0P": 111.0
        ]
        #expect(MacHardware.averageCPUTemperature(
            availableKeys: Set(invalidTemperatures.keys),
            read: { invalidTemperatures[$0] }
        ) == nil)
    }

    /// Fan ranges come from the SMC keys, one to eight fans, and anything
    /// missing or out of range yields no fans at all.
    @Test func fanRanges() {
        for count in 1...8 {
            var values = ["FNum": Double(count)]
            for id in 0..<count {
                values["F\(id)Mn"] = Double(1_000 + id)
                values["F\(id)Mx"] = Double(8_000 + id)
            }
            #expect(MacHardware.fanRanges(read: { values[$0] }).count == count)
        }

        let invalidFanData: [[String: Double]] = [
            ["FNum": 0],
            ["FNum": 9],
            ["FNum": 1.5],
            ["FNum": .greatestFiniteMagnitude],
            ["FNum": 1, "F0Mn": 1_000],
            ["FNum": 1, "F0Mn": -1, "F0Mx": 8_000],
            ["FNum": 1, "F0Mn": 8_000, "F0Mx": 8_000],
            ["FNum": 1, "F0Mn": 1_000, "F0Mx": 20_001],
            ["FNum": 1, "F0Mn": 1_000, "F0Mx": .greatestFiniteMagnitude]
        ]
        #expect(invalidFanData.allSatisfy { values in
            MacHardware.fanRanges(read: { values[$0] }).isEmpty
        })
    }

    /// Intel Macs control at most two fans; Apple Silicon has no such limit.
    /// The reported support level requires a readable mode on every fan.
    @Test func fanControlSupport() {
        let threeFans = (0..<3).map { FanRange(id: $0, minimumRPM: 1_000, maximumRPM: 8_000) }
        #if arch(arm64)
        #expect(MacHardware.supportsFanControl(threeFans, readMode: { _ in .automatic }))
        #else
        #expect(!MacHardware.supportsFanControl(threeFans, readMode: { _ in .automatic }))
        #endif
        #expect(!MacHardware.supportsFanControl(
            [FanRange(id: 0, minimumRPM: 1_000, maximumRPM: 8_000)],
            readMode: { _ in nil }
        ))

        #expect(MacHardware.supportLevel(model: "Mac17,9", fanCount: 2, fanControlSupported: true) == .verified)
        #expect(MacHardware.supportLevel(model: "Mac17,9", fanCount: 1, fanControlSupported: true) == .unsupported)
        #expect(MacHardware.supportLevel(model: "Mac16,1", fanCount: 1, fanControlSupported: true) == .knownKeys)
        #expect(MacHardware.supportLevel(model: "Mac17,9", fanCount: 2, fanControlSupported: false) == .unsupported)
    }

    /// Apple modes decode from the raw value; the Intel mask carries one bit
    /// per fan. Telemetry validates RPM and formats the display strings.
    @Test func fanModesAndTelemetryText() {
        #expect(MacHardware.appleFanMode(0) == .automatic)
        #expect(MacHardware.appleFanMode(1) == .forced)
        #expect(MacHardware.appleFanMode(3) == .system)
        #expect(MacHardware.appleFanMode(2) == nil)
        #expect(MacHardware.appleFanMode(.nan) == nil)

        #expect(MacHardware.intelFanMode(0, fanID: 0) == .automatic)
        #expect(MacHardware.intelFanMode(1, fanID: 0) == .forced)
        #expect(MacHardware.intelFanMode(1, fanID: 1) == .automatic)
        #expect(MacHardware.intelFanMode(2, fanID: 1) == .forced)
        #expect(MacHardware.intelFanMode(3, fanID: 2) == nil)

        let fanTelemetry = FanTelemetry(id: 0, actualRPM: 2_345.4, targetRPM: .nan, mode: .forced)
        #expect(fanTelemetry.actualRPMText == "2345 RPM")
        #expect(fanTelemetry.targetRPMText == "—")
        #expect(fanTelemetry.modeText == "Forced")

        #expect(MacHardware.validRPM(0) == 0)
        #expect(MacHardware.validRPM(20_000) == 20_000)
        #expect(MacHardware.validRPM(-1) == nil)
        #expect(MacHardware.validRPM(20_001) == nil)
        #expect(FanTelemetry(id: 0, actualRPM: -1, targetRPM: 20_001, mode: .automatic).actualRPM == nil)
    }
}

@Suite("Fan control policy")
struct FanControlPolicyTests {
    private let validState = ControlState(enabled: true, percentage: 50, heartbeat: 100, ownerUID: 501)

    /// Control needs an enabled state, an in-range percentage, a fresh
    /// heartbeat with a finite timeout, and safe thermal pressure.
    @Test func allowsControl() {
        #expect(ControlPolicy.allowsControl(
            state: validState,
            now: 104,
            thermalPressureIsSafe: true
        ))
        #expect(!ControlPolicy.allowsControl(
            state: validState,
            now: 106,
            thermalPressureIsSafe: true
        ))
        // A heartbeat from the future is not fresh.
        #expect(!ControlPolicy.allowsControl(
            state: validState,
            now: 99,
            thermalPressureIsSafe: true
        ))
        #expect(!ControlPolicy.allowsControl(
            state: validState,
            now: 104,
            heartbeatTimeout: .infinity,
            thermalPressureIsSafe: true
        ))
        #expect(!ControlPolicy.allowsControl(
            state: ControlState(enabled: false, percentage: 50, heartbeat: 100, ownerUID: 501),
            now: 104,
            thermalPressureIsSafe: true
        ))
        #expect(!ControlPolicy.allowsControl(
            state: validState,
            now: 104,
            thermalPressureIsSafe: false
        ))
        #expect(!ControlPolicy.allowsControl(
            state: ControlState(enabled: true, percentage: 101, heartbeat: 100, ownerUID: 501),
            now: 104,
            thermalPressureIsSafe: true
        ))
    }

    /// Confirmation requires forced fan modes, the right owner, an in-range
    /// percentage, and a fresh heartbeat.
    @Test func confirmationMatching() {
        let acknowledgement = ControlAcknowledgement(heartbeat: 100, percentage: 50, ownerUID: 501)
        #expect(acknowledgement == ControlAcknowledgement(heartbeat: 100, percentage: 50, ownerUID: 501))
        #expect(acknowledgement != ControlAcknowledgement(heartbeat: 100, percentage: 51, ownerUID: 501))

        let confirmationFan = FanRange(id: 0, minimumRPM: 2_000, maximumRPM: 8_000)
        let acknowledgedTelemetry = [FanTelemetry(
            id: 0,
            actualRPM: 5_000,
            targetRPM: 5_500,
            mode: .forced
        )]
        let fanModesAreForced = ControlPolicy.fanModesAreForced(
            fans: [confirmationFan],
            telemetry: acknowledgedTelemetry
        )
        #expect(fanModesAreForced)
        #expect(ControlPolicy.confirmationMatches(
            acknowledgement,
            ownerUID: 501,
            now: 102,
            fanModesAreForced: fanModesAreForced
        ))
        #expect(!ControlPolicy.fanModesAreForced(
            fans: [confirmationFan],
            telemetry: [FanTelemetry(
                id: 0,
                actualRPM: 5_000,
                targetRPM: 5_500,
                mode: .automatic
            )]
        ))

        // The acknowledged percentage may trail the request; only the heartbeat is checked.
        let trailingAcknowledgement = ControlAcknowledgement(heartbeat: 100, percentage: 64, ownerUID: 501)
        #expect(ControlPolicy.confirmationMatches(
            trailingAcknowledgement,
            ownerUID: 501,
            now: 102,
            fanModesAreForced: true
        ))

        #expect(!ControlPolicy.confirmationMatches(
            acknowledgement,
            ownerUID: 501,
            now: 102,
            fanModesAreForced: false
        ))
        #expect(!ControlPolicy.confirmationMatches(
            acknowledgement,
            ownerUID: 501,
            now: 103,
            fanModesAreForced: true
        ))
        #expect(!ControlPolicy.confirmationMatches(
            acknowledgement,
            ownerUID: 502,
            now: 102,
            fanModesAreForced: true
        ))
        #expect(!ControlPolicy.confirmationMatches(
            acknowledgement,
            ownerUID: 501,
            now: 102,
            fanModesAreForced: true,
            heartbeatTimeout: .infinity
        ))
        #expect(!ControlPolicy.confirmationMatches(
            ControlAcknowledgement(heartbeat: 100, percentage: 101, ownerUID: 501),
            ownerUID: 501,
            now: 102,
            fanModesAreForced: true
        ))
    }

    /// The deadline fails as never confirmed if control never took, and as
    /// lost once it had been confirmed and then dropped.
    @Test func confirmationDeadline() {
        var confirmation = ControlConfirmationDeadline()

        confirmation.start(at: 100)
        let withinDeadline = confirmation.failure(isConfirmed: false, at: 103.9)
        #expect(withinDeadline == nil)
        let confirmedAtDeadline = confirmation.failure(isConfirmed: true, at: 104)
        #expect(confirmedAtDeadline == nil)

        confirmation.start(at: 100)
        let neverConfirmed = confirmation.failure(isConfirmed: false, at: 104)
        #expect(neverConfirmed == .neverConfirmed)

        confirmation.start(at: 200)
        let firstConfirmation = confirmation.failure(isConfirmed: true, at: 201)
        #expect(firstConfirmation == nil)
        let afterConfirmation = confirmation.failure(isConfirmed: false, at: 202)
        #expect(afterConfirmation == nil)
        let stillConfirmed = confirmation.failure(isConfirmed: true, at: 206)
        #expect(stillConfirmed == nil)
        let stillWithinTimeout = confirmation.failure(isConfirmed: false, at: 207)
        #expect(stillWithinTimeout == nil)
        let lost = confirmation.failure(isConfirmed: false, at: 211)
        #expect(lost == .lost)
    }

    /// One poll runs at a time, and the heartbeat only refreshes when enabled.
    /// The active transition notifies exactly once per loss of control.
    @Test func loopScheduleAndTransitions() {
        var controlLoop = ControlLoopSchedule()

        let firstTick = controlLoop.tick(isEnabled: true)
        #expect(firstTick == ControlLoopWork(refreshHeartbeat: true, startPoll: true))

        for _ in 0..<10 {
            let tick = controlLoop.tick(isEnabled: true)
            #expect(tick == ControlLoopWork(refreshHeartbeat: true, startPoll: false))
        }

        controlLoop.finishPoll()
        let afterFinishPoll = controlLoop.tick(isEnabled: true)
        #expect(afterFinishPoll == ControlLoopWork(refreshHeartbeat: true, startPoll: true))

        controlLoop.finishPoll()
        let disabledTick = controlLoop.tick(isEnabled: false)
        #expect(disabledTick == ControlLoopWork(refreshHeartbeat: false, startPoll: true))

        var activeControlTransition = ActiveControlTransition()
        let notifications = [
            activeControlTransition.shouldNotify(isEnabled: true, isActive: false),
            activeControlTransition.shouldNotify(isEnabled: true, isActive: true),
            activeControlTransition.shouldNotify(isEnabled: true, isActive: false),
            activeControlTransition.shouldNotify(isEnabled: true, isActive: false),
            activeControlTransition.shouldNotify(isEnabled: true, isActive: true),
            activeControlTransition.shouldNotify(isEnabled: false, isActive: false)
        ]
        #expect(notifications == [false, false, true, false, false, false])
    }

    /// A missing temperature or no fans is a problem; control that is enabled
    /// but inactive is a problem; disabled and inactive is automatic.
    @Test func displayState() {
        #expect(ControlDisplayState(hasTemperature: false, fanCount: 2, isEnabled: false, isActive: false) == .problem)
        #expect(ControlDisplayState(hasTemperature: true, fanCount: 0, isEnabled: false, isActive: false) == .problem)
        #expect(ControlDisplayState(hasTemperature: true, fanCount: 2, isEnabled: false, isActive: false) == .automatic)
        #expect(ControlDisplayState(hasTemperature: true, fanCount: 2, isEnabled: false, isActive: true) == .problem)
        #expect(ControlDisplayState(hasTemperature: true, fanCount: 2, isEnabled: true, isActive: false) == .problem)
        #expect(ControlDisplayState(hasTemperature: true, fanCount: 2, isEnabled: true, isActive: true) == .active)
    }

    /// Resuming after sleep needs a fresh wake poll with a temperature reading.
    /// A launch resume runs once and only succeeds with temperature, supported
    /// fans, and a current helper.
    @Test func wakeAndLaunchRecovery() {
        var wakeRecovery = WakeRecovery()

        let oldPoll = wakeRecovery.beginPoll()
        #expect(oldPoll == false)

        wakeRecovery.prepareForSleep(wasEnabled: true)
        let wokeAfterEnabledSleep = wakeRecovery.didWake()
        #expect(wokeAfterEnabledSleep)

        let pollWhileSleeping = wakeRecovery.beginPoll()
        #expect(pollWhileSleeping == nil)

        let stalePollResult = wakeRecovery.finishPoll(isWakePoll: false, hasTemperature: true)
        #expect(!stalePollResult)

        let firstWakePoll = wakeRecovery.beginPoll()
        #expect(firstWakePoll == true)
        // No temperature yet: resume stays pending and another poll is required.
        let withoutTemperature = wakeRecovery.finishPoll(isWakePoll: true, hasTemperature: false)
        #expect(!withoutTemperature)

        let retryWakePoll = wakeRecovery.beginPoll()
        #expect(retryWakePoll == true)
        let resumed = wakeRecovery.finishPoll(isWakePoll: true, hasTemperature: true)
        #expect(resumed)

        wakeRecovery.prepareForSleep(wasEnabled: false)
        let wokeAfterDisabledSleep = wakeRecovery.didWake()
        #expect(!wokeAfterDisabledSleep)

        wakeRecovery.prepareForSleep(wasEnabled: true)
        wakeRecovery.cancelResume()
        let wokeAfterCancel = wakeRecovery.didWake()
        #expect(!wokeAfterCancel)

        for (requested, temperature, fans, helper) in [
            (false, true, true, true),
            (true, false, true, true),
            (true, true, false, true),
            (true, true, true, false),
            (true, true, true, true)
        ] {
            var launchRecovery = LaunchRecovery(requested: requested)
            let finished = launchRecovery.finishFirstPoll(
                hasTemperature: temperature,
                hasSupportedFans: fans,
                helperIsCurrent: helper
            )
            #expect(finished == (requested && temperature && fans && helper))
            // The first poll is the only one that can resume control.
            let secondPoll = launchRecovery.finishFirstPoll(
                hasTemperature: true,
                hasSupportedFans: true,
                helperIsCurrent: true
            )
            #expect(!secondPoll)
        }

        var cancelledLaunchRecovery = LaunchRecovery(requested: true)
        cancelledLaunchRecovery.cancelResume()
        let finishedAfterCancel = cancelledLaunchRecovery.finishFirstPoll(
            hasTemperature: true,
            hasSupportedFans: true,
            helperIsCurrent: true
        )
        #expect(!finishedAfterCancel)
    }
}

@Suite("Secure files, history, and recording")
struct FanCurveStateTests {
    /// State files must be regular, owned by the caller, private, and small;
    /// symlinks and oversized files are refused. The launch daemon template
    /// must be installed with the caller's UID substituted.
    @Test func secureFilesAndHelperInstallation() throws {
        let secureFileDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fancurve-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: secureFileDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: secureFileDirectory) }

        let secureFile = secureFileDirectory.appendingPathComponent("state")
        try Data("safe".utf8).write(to: secureFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secureFile.path)
        #expect(SecureRegularFile.read(
            secureFile.path,
            ownerUID: getuid(),
            forbiddenPermissions: 0o077,
            maxSize: 4_096
        ) == Data("safe".utf8))

        let secureFileLink = secureFileDirectory.appendingPathComponent("state-link")
        try FileManager.default.createSymbolicLink(at: secureFileLink, withDestinationURL: secureFile)
        #expect(SecureRegularFile.read(
            secureFileLink.path,
            ownerUID: getuid(),
            forbiddenPermissions: 0o077,
            maxSize: 4_096
        ) == nil)

        try Data(repeating: 0, count: 4_097).write(to: secureFile)
        #expect(SecureRegularFile.read(
            secureFile.path,
            ownerUID: getuid(),
            forbiddenPermissions: 0o077,
            maxSize: 4_096
        ) == nil)

        #expect(!HelperInstallation.isSecure(
            helperPath: "/nonexistent/fancurve-helper",
            launchDaemonPath: "/nonexistent/fancurve-helper.plist"
        ))

        let launchDaemonTemplate = Data("/tmp/fancurve-__OWNER_UID__.json __OWNER_UID__".utf8)
        #expect(HelperInstallation.launchDaemonMatches(
            template: launchDaemonTemplate,
            installed: Data("/tmp/fancurve-501.json 501".utf8),
            ownerUID: 501
        ))
        #expect(!HelperInstallation.launchDaemonMatches(
            template: launchDaemonTemplate,
            installed: Data("/tmp/fancurve-502.json 502".utf8),
            ownerUID: 501
        ))
    }

    /// Samples are thinned by interval and retention, a change in whether the
    /// fan percentage is known is always recorded, and decoding enforces size,
    /// ordering, range, and count limits.
    @Test func historyAppendingAndDecoding() throws {
        let history = TemperatureHistory.appending(
            70,
            fanPercentage: 50,
            at: 100_000,
            to: [
                TemperatureSample(timestamp: 10_000, temperature: 40, fanPercentage: 10),
                TemperatureSample(timestamp: 99_950, temperature: 60, fanPercentage: 40)
            ],
            interval: 60,
            retention: 86_400
        )
        // The stale sample is dropped; the fresh one is too recent to add another.
        #expect(history == [TemperatureSample(timestamp: 99_950, temperature: 60, fanPercentage: 40)])
        #expect(TemperatureHistory.appending(
            70,
            fanPercentage: 50,
            at: 100_010,
            to: history
        ) == history + [TemperatureSample(timestamp: 100_010, temperature: 70, fanPercentage: 50)])

        let stoppedHistory = TemperatureHistory.appending(
            71,
            at: 100_020,
            to: history + [TemperatureSample(timestamp: 100_010, temperature: 70, fanPercentage: 50)]
        )
        #expect(stoppedHistory.last == TemperatureSample(timestamp: 100_020, temperature: 71))
        #expect(TemperatureHistory.appending(
            72,
            fanPercentage: 50,
            at: 100_030,
            to: stoppedHistory
        ).last == TemperatureSample(timestamp: 100_030, temperature: 72, fanPercentage: 50))

        let oldHistory = TemperatureHistory.decode(from: Data(#"[{"timestamp":100,"temperature":55}]"#.utf8))
        #expect(oldHistory == [TemperatureSample(timestamp: 100, temperature: 55)])
        #expect(TemperatureHistory.decode(from: Data(repeating: 0, count: 1_048_577)) == nil)
        #expect(TemperatureHistory.decode(from: Data(
            #"[{"timestamp":101,"temperature":55},{"timestamp":100,"temperature":56}]"#.utf8
        )) == nil)
        #expect(TemperatureHistory.decode(from: Data(#"[{"timestamp":100,"temperature":111}]"#.utf8)) == nil)
        let tooManySamples = try JSONEncoder().encode(
            (0...1_500).map { TemperatureSample(timestamp: Double($0), temperature: 55) }
        )
        #expect(TemperatureHistory.decode(from: tooManySamples) == nil)
    }

    /// One JSON object per line, private permissions, and the file rotates to
    /// `.1` once an entry would push it past the size limit.
    @Test func eventRecorderWritesAndRotates() throws {
        let recorderDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FanCurveRecorderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: recorderDirectory) }
        let recorderURL = recorderDirectory.appendingPathComponent("control-events.jsonl")
        let recorder = ControlEventRecorder(fileURL: recorderURL, maximumBytes: 1_024)

        recorder.record(ControlEvent(
            kind: .launched,
            timestamp: 100,
            message: "check",
            expectedPercentage: 40,
            state: ControlStateSnapshot(
                present: true,
                valid: true,
                enabled: true,
                percentage: 40,
                heartbeatAge: 0.2
            ),
            acknowledgement: ControlAcknowledgementSnapshot(
                present: true,
                valid: true,
                percentage: 40,
                heartbeatAge: 0.3
            ),
            fans: [ControlFanSnapshot(id: 0, mode: "forced", actualRPM: 3_000, targetRPM: 3_100)],
            temperature: 70,
            pollDuration: 0.5,
            thermalState: "nominal"
        ))
        #expect(FileManager.default.fileExists(atPath: recorderURL.path))

        let firstRecording = try String(contentsOf: recorderURL, encoding: .utf8)
        #expect(firstRecording.split(whereSeparator: \.isNewline).count == 1)
        #expect(firstRecording.contains(#""kind":"launched""#))
        #expect(firstRecording.contains(#""heartbeatAge":0.2"#))

        for index in 0..<20 {
            recorder.record(ControlEvent(
                kind: .controlLost,
                timestamp: Double(101 + index),
                message: String(repeating: "x", count: 120)
            ))
        }

        #expect(
            FileManager.default.fileExists(atPath: recorderURL.path + ".1"),
            "recorder must rotate; files: \((try? FileManager.default.contentsOfDirectory(atPath: recorderDirectory.path)) ?? []) size: \((try? Data(contentsOf: recorderURL).count) ?? -1)"
        )
        let finalSize = try Data(contentsOf: recorderURL).count
        #expect(finalSize <= 1_024)
    }
}

import Observation
import PopKit
import SwiftUI

/// Runs the PostureMachine over hinge readings and publishes curl, pop depth and page
/// events. Readings come from the Duo (`readsHinge(into:)`), or from the debug panel and
/// scripts, which take over while they're active (the simulator's hinge moves by hand only).
@MainActor
@Observable
final class HingeModel {
    enum Source: Sendable {
        case device
        case debug
    }

    private(set) var state = PostureState.initial
    /// The debug panel or a script is driving; device readings are ignored meanwhile.
    private(set) var overridden = LaunchOptions.debugHinge
    private(set) var lastDeviceAngle: Double?

    @ObservationIgnored var onEvent: @MainActor (PostureEvent) -> Void = { _ in }
    @ObservationIgnored private let machine: PostureMachine
    @ObservationIgnored private var lastSample: HingeSample?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var scriptTask: Task<Void, Never>?
    @ObservationIgnored private let origin = ContinuousClock.now
    /// `-logHinge YES` writes every reading and posture event to Documents/hinge.log.
    @ObservationIgnored private let fileLog = LaunchOptions.logHinge ? FileLog(name: "hinge") : nil

    init(config: PostureConfig = .standard) {
        machine = PostureMachine(config: config)
    }

    var config: PostureConfig { machine.config }

    /// Starts in the debug posture (open flat) when overridden, then plays any launch script.
    func start(script: [HingeScript.Move]) {
        if overridden, lastSample == nil {
            ingest(posture: .fullyOpen, degrees: 180, from: .debug)
        }
        if !script.isEmpty { play(script) }
        if let angle = LaunchOptions.hingeAngle { sweep(to: angle) }
    }

    /// Sweeps the debug hinge from where it is to `angle` and holds it there.
    func sweep(to angle: Double, interval: Duration = .milliseconds(60)) {
        setOverride(true)
        scriptTask?.cancel()
        let from = state.angle > 0 ? state.angle : 180
        let angles = HingeScript.sweep(from: from, to: angle)
        scriptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            for value in angles {
                guard !Task.isCancelled, let self else { return }
                self.ingest(posture: Self.posture(for: value), degrees: value, from: .debug)
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    func ingest(posture: HingePosture, degrees: Double, from source: Source) {
        if source == .device { lastDeviceAngle = degrees }
        fileLog?.append("\(source == .device ? "device" : "debug") \(posture) \(String(format: "%.1f", degrees))° overridden=\(overridden)")
        guard (source == .debug) == overridden else { return }
        apply(HingeSample(posture: posture, angle: degrees, time: elapsed()))
    }

    /// Hands the hinge to the debug panel (true) or back to the device (false).
    func setOverride(_ on: Bool) {
        overridden = on
        if !on { scriptTask?.cancel() }
    }

    /// Plays scripted moves at a steady rate, like DeviceHub's interpolated sweep.
    func play(_ moves: [HingeScript.Move], interval: Duration = .milliseconds(40)) {
        setOverride(true)
        scriptTask?.cancel()
        scriptTask = Task { [weak self] in
            for move in moves {
                for angle in HingeScript.angles(for: move) {
                    guard !Task.isCancelled, let self else { return }
                    self.ingest(posture: Self.posture(for: angle), degrees: angle, from: .debug)
                    do { try await Task.sleep(for: interval) } catch { return }
                }
            }
        }
    }

    static func posture(for degrees: Double) -> HingePosture {
        if degrees <= 0.5 { return .closed }
        return degrees >= 179.5 ? .fullyOpen : .partiallyOpen
    }

    private func apply(_ sample: HingeSample) {
        let (next, events) = machine.reduce(state, sample)
        state = next
        lastSample = sample
        for event in events {
            fileLog?.append("event \(event) phase \(state.phase)")
            onEvent(event)
        }
        scheduleTick()
    }

    /// Closing needs time to pass without new readings, so re-send the last one after the hold.
    private func scheduleTick() {
        tickTask?.cancel()
        guard state.needsTick, let last = lastSample else { return }
        let wait = Duration.seconds(machine.config.closeHold) + .milliseconds(50)
        tickTask = Task { [weak self] in
            do { try await Task.sleep(for: wait) } catch { return }
            guard let self else { return }
            self.apply(HingeSample(posture: last.posture, angle: last.angle, time: self.elapsed()))
        }
    }

    private func elapsed() -> TimeInterval {
        let duration = ContinuousClock.now - origin
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

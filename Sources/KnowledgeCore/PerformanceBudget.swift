import Foundation

/// Policy, not a frame-rate cap. Rendering, edits, playback and durable saves are
/// never disabled. Only replaceable artwork work and cache residency are adjusted.
public struct PerformanceBudget: Equatable, Sendable {
    public enum ThermalPressure: Sendable { case nominal, fair, serious, critical }
    public let artworkConcurrency: Int
    public let artworkBytes: Int
    public let editorialBytes: Int
    public let customCoverBytes: Int

    public init(lowPower: Bool, thermal: ThermalPressure, memoryPressure: Bool = false) {
        let constrained = lowPower || thermal == .serious || thermal == .critical
        artworkConcurrency = constrained || memoryPressure ? 1 : 2
        artworkBytes = (memoryPressure ? 4 : constrained ? 12 : 24) * 1_048_576
        editorialBytes = (memoryPressure ? 2 : constrained ? 6 : 12) * 1_048_576
        customCoverBytes = (memoryPressure ? 2 : constrained ? 6 : 12) * 1_048_576
    }

    /// Foreground bookkeeping sleeps until useful work is due. A failed save gets
    /// a bounded retry instead of spinning. Deadlines remain wall-clock based.
    public static func nextWakeDelay(now: Date, checkpointIn: TimeInterval, deadlines: [Date]) -> TimeInterval {
        let delay = min(max(0, checkpointIn), deadlines.map { $0.timeIntervalSince(now) }.min() ?? 30)
        return delay <= 0 ? 1 : delay
    }
}

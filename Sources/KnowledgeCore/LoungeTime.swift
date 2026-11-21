import Foundation

public struct StudyInterval: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var start: Date
    public var duration: TimeInterval
    public var sourceID: UUID?

    public var end: Date { start.addingTimeInterval(duration) }
    public init(start: Date, duration: TimeInterval, sourceID: UUID?) {
        self.start = start
        self.duration = duration
        self.sourceID = sourceID
    }

    /// Calendar days can be shorter or longer than 24 hours.
    public func seconds(in day: DateInterval) -> TimeInterval {
        max(0, min(end, day.end).timeIntervalSince(max(start, day.start)))
    }
}

public struct LoungeLedger {
    public private(set) var records: [StudyInterval]
    private var active: Bool = false
    private var sourceID: UUID?
    private var beganAt = Date.distantPast
    private var beganUptime: TimeInterval = 0

    public init(records: [StudyInterval] = []) { self.records = records }

    public mutating func transition(active next: Bool, sourceID nextSource: UUID?, now: Date, uptime: TimeInterval) {
        guard next != active || (next && nextSource != sourceID) else { return }
        checkpoint(now: now, uptime: uptime)
        active = next
        sourceID = nextSource
        beganAt = now
        beganUptime = uptime
    }

    public mutating func checkpoint(now: Date, uptime: TimeInterval) {
        guard active else { return }
        let elapsed = uptime - beganUptime
        guard elapsed.isFinite, elapsed > 0 else { return }
        if let last = records.indices.last, records[last].sourceID == sourceID,
            abs(records[last].end.timeIntervalSince(beganAt)) < 0.1 {
            records[last].duration += elapsed
        } else {
            records.append(StudyInterval(start: beganAt, duration: elapsed, sourceID: sourceID))
        }
        beganAt = now
        beganUptime = uptime
    }

    public func snapshot(now: Date, uptime: TimeInterval) -> [StudyInterval] {
        var copy = self
        copy.checkpoint(now: now, uptime: uptime)
        return copy.records
    }
}

public struct LoungeCountdown: Codable, Equatable, Sendable {
    public var deadline: Date?
    public var pausedSeconds: TimeInterval?
    public var isStarted: Bool { deadline != nil || pausedSeconds != nil }

    public init() {}
    public func remaining(at now: Date) -> TimeInterval {
        max(0, deadline?.timeIntervalSince(now) ?? pausedSeconds ?? 0)
    }
    public mutating func start(minutes: Int, at now: Date) {
        pausedSeconds = nil
        deadline = now.addingTimeInterval(Double(min(120, max(15, minutes))) * 60)
    }
    public mutating func pause(at now: Date) {
        guard let deadline, deadline > now else { return }
        pausedSeconds = deadline.timeIntervalSince(now)
        self.deadline = nil
    }
    public mutating func resume(at now: Date) {
        guard let pausedSeconds, pausedSeconds > 0 else { return }
        deadline = now.addingTimeInterval(pausedSeconds)
        self.pausedSeconds = nil
    }
    public mutating func consumeCompletion(at now: Date) -> Bool {
        guard let deadline, deadline <= now else { return false }
        self = LoungeCountdown()
        return true
    }
}

import os

/// Points of Interest for Release-device Instruments recordings. No document
/// titles, identifiers, user content or URLs are included in these events.
enum PerformanceTrace {
    static let signposter = OSSignposter(subsystem: "org.knowledge-studio.prototype", category: "Performance")
}

import Foundation

/// Decides when an expanded bar has been abandoned.
///
/// Deliberately free of AppKit so the timing rules can be tested directly: the
/// caller feeds it "is the pointer on the bar right now", it answers "collapse".
/// A grace period keeps the bar open while the pointer clips a corner or crosses
/// the gap to the hover card and back.
struct HoverWatchdog {
    /// How long the pointer must stay away before the bar collapses.
    var grace: TimeInterval = 0.6

    private var awaySince: Date?

    init(grace: TimeInterval = 0.6) {
        self.grace = grace
    }

    /// Returns true exactly once, on the tick that the grace period expires.
    mutating func shouldCollapse(pointerInside: Bool, now: Date) -> Bool {
        guard !pointerInside else {
            awaySince = nil
            return false
        }
        guard let since = awaySince else {
            awaySince = now
            return false
        }
        if now.timeIntervalSince(since) >= grace {
            awaySince = nil
            return true
        }
        return false
    }

    /// Forgets any in-flight countdown — used when the bar collapses for another
    /// reason, or while a context menu is up.
    mutating func reset() {
        awaySince = nil
    }
}

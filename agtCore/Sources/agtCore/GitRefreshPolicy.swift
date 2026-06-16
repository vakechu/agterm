import Foundation

/// The pure decision behind whether a session's git status should be refreshed
/// now — the OSC-7-flood debounce / coalesce predicate, lifted out of the
/// `Process` side so it can be unit-tested without git.
///
/// `Sendable` and stateless: the throttle state (last-ran cwd/timestamp,
/// in-flight set) lives on the `@MainActor` service; this type only encodes the
/// rule applied to those reads.
public enum GitRefreshPolicy: Sendable {
    /// Decides whether to spawn a git refresh for a session.
    ///
    /// - `false` if a refresh for that session is already in flight (coalesce).
    /// - `false` if `cwd == lastRanCwd` and the last run was within `minInterval`
    ///   of `now` (a prompt redraw re-reporting the same cwd must not re-spawn).
    /// - `true` for a new cwd (a `cd` to a different directory always refreshes),
    ///   or for the same cwd once `minInterval` has elapsed (the active-timer poll).
    public static func shouldRefresh(cwd: String, lastRanCwd: String?, lastRanAt: Date?,
                                     now: Date, minInterval: TimeInterval, inFlight: Bool) -> Bool {
        if inFlight { return false }
        // a new cwd always refreshes (coalesce-to-latest: cd a; cd b runs against b)
        if cwd != lastRanCwd { return true }
        // same cwd: refresh only once the min interval has elapsed
        guard let lastRanAt else { return true }
        return now.timeIntervalSince(lastRanAt) >= minInterval
    }
}

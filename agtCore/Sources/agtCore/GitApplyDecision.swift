import Foundation

/// The pure decision for what to do with a finished git-status run when the
/// completion hop reaches the main actor — the three guards that protect the
/// `@Observable` write, lifted out of the service so they can be unit-tested
/// without a `Session` or `Process`.
///
/// `Sendable` and stateless: it maps the finished run (the cwd it ran for, the
/// session's *current* cwd, success/failure, the parsed value, and the existing
/// value) to one of three actions; the service performs the side effect.
public enum GitApplyDecision: Sendable {
    /// What the completion hop should do with a finished run.
    public enum Action: Equatable, Sendable {
        /// The cwd changed under the run (a `cd a; cd b` race). Discard the result
        /// and re-enqueue a refresh for the latest cwd.
        case reEnqueue
        /// A transient failure/timeout, or a value identical to the current one.
        /// Leave `session.gitStatus` untouched (don't clobber, don't invalidate).
        case keepExisting
        /// Write the new value (it differs from the existing one).
        case write(GitStatus?)
    }

    /// Decides the completion-hop action for a finished run.
    ///
    /// - `reEnqueue` when `currentCwd != ranCwd` (stale-result clobber guard).
    /// - `keepExisting` when the run failed (transient-failure guard: never clobber
    ///   a known status to nil), or when the parsed value equals `existing`
    ///   (equality-gate: an `@Observable` write invalidates regardless of value).
    /// - `write(parsed)` only when the cwd still matches, the run succeeded, and the
    ///   value actually changed.
    public static func decide(ranCwd: String, currentCwd: String?, succeeded: Bool,
                              parsed: GitStatus?, existing: GitStatus?) -> Action {
        guard currentCwd == ranCwd else { return .reEnqueue }
        guard succeeded else { return .keepExisting }
        guard parsed != existing else { return .keepExisting }
        return .write(parsed)
    }
}

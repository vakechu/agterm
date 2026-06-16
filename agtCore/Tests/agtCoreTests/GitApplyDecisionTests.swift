import Foundation
import Testing
@testable import agtCore

struct GitApplyDecisionTests {
    private static let dirty = GitStatus(branch: "main", dirty: 1)
    private static let clean = GitStatus(branch: "main")

    @Test func staleResultReEnqueues() {
        // the session's cwd moved on (cd a; cd b) while the run for /a finished
        let action = GitApplyDecision.decide(ranCwd: "/a", currentCwd: "/b", succeeded: true,
                                             parsed: Self.dirty, existing: nil)
        #expect(action == .reEnqueue)
    }

    @Test func staleResultWinsOverFailure() {
        // a stale cwd re-enqueues even when the run failed (cwd check is first)
        let action = GitApplyDecision.decide(ranCwd: "/a", currentCwd: "/b", succeeded: false,
                                             parsed: nil, existing: Self.clean)
        #expect(action == .reEnqueue)
    }

    @Test func failureKeepsExisting() {
        // transient failure/timeout must never clobber a known status to nil
        let action = GitApplyDecision.decide(ranCwd: "/a", currentCwd: "/a", succeeded: false,
                                             parsed: nil, existing: Self.dirty)
        #expect(action == .keepExisting)
    }

    @Test func identicalValueKeepsExisting() {
        // equality-gate: a 3s tick re-reporting the same status must not write
        let action = GitApplyDecision.decide(ranCwd: "/a", currentCwd: "/a", succeeded: true,
                                             parsed: Self.dirty, existing: Self.dirty)
        #expect(action == .keepExisting)
    }

    @Test func changedValueWrites() {
        let action = GitApplyDecision.decide(ranCwd: "/a", currentCwd: "/a", succeeded: true,
                                             parsed: Self.dirty, existing: Self.clean)
        #expect(action == .write(Self.dirty))
    }

    @Test func firstNonNilFromNilWrites() {
        // first successful run for a session (existing nil) writes the parsed value
        let action = GitApplyDecision.decide(ranCwd: "/a", currentCwd: "/a", succeeded: true,
                                             parsed: Self.clean, existing: nil)
        #expect(action == .write(Self.clean))
    }

    @Test func clearedToNilWrites() {
        // a successful run that parsed nil (cwd left a repo) over a known status is a
        // real change → write nil (distinct from a FAILURE, which keeps the prior)
        let action = GitApplyDecision.decide(ranCwd: "/a", currentCwd: "/a", succeeded: true,
                                             parsed: nil, existing: Self.dirty)
        #expect(action == .write(nil))
    }

    @Test func nilCurrentCwdReEnqueuesWhenRanCwdNonEmpty() {
        // the session lost its cwd report; ranCwd no longer matches → re-enqueue
        let action = GitApplyDecision.decide(ranCwd: "/a", currentCwd: nil, succeeded: true,
                                             parsed: Self.dirty, existing: nil)
        #expect(action == .reEnqueue)
    }
}

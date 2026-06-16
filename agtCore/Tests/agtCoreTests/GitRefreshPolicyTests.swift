import Foundation
import Testing
@testable import agtCore

struct GitRefreshPolicyTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let minInterval: TimeInterval = 3

    @Test(arguments: [
        // (cwd, lastRanCwd, lastRanSecondsAgo, inFlight, expected)
        ("/a", "/a", 1.0, true, false),   // in-flight always blocks
        ("/a", "/a", 1.0, false, false),  // same cwd within min-interval
        ("/a", "/a", 5.0, false, true),   // same cwd after min-interval (active poll)
        ("/a", "/a", 3.0, false, true),   // same cwd exactly at min-interval boundary
        ("/b", "/a", 1.0, false, true),   // new cwd refreshes even within interval
        ("/a", nil, 0.0, false, true),    // first run (no prior cwd)
    ])
    func shouldRefreshDecision(cwd: String, lastRanCwd: String?, lastRanSecondsAgo: Double, inFlight: Bool, expected: Bool) {
        let lastRanAt = lastRanCwd == nil ? nil : Self.now.addingTimeInterval(-lastRanSecondsAgo)
        let result = GitRefreshPolicy.shouldRefresh(cwd: cwd, lastRanCwd: lastRanCwd, lastRanAt: lastRanAt,
                                                     now: Self.now, minInterval: Self.minInterval, inFlight: inFlight)
        #expect(result == expected)
    }

    @Test func coalescesToLatestCwd() {
        // walk the cd a; cd b sequence through the policy and assert the LATEST cwd
        // is the one that ultimately runs, with no spawn for the superseded /a.
        var lastRanCwd: String?
        var lastRanAt: Date?
        var inFlight = false

        // cd a: nothing running, /a is new → spawn for /a, mark in-flight
        #expect(GitRefreshPolicy.shouldRefresh(cwd: "/a", lastRanCwd: lastRanCwd, lastRanAt: lastRanAt,
                                               now: Self.now, minInterval: Self.minInterval, inFlight: inFlight))
        lastRanCwd = "/a"; lastRanAt = Self.now; inFlight = true

        // cd b arrives while /a is still in flight → coalesced away (no second spawn)
        #expect(!GitRefreshPolicy.shouldRefresh(cwd: "/b", lastRanCwd: lastRanCwd, lastRanAt: lastRanAt,
                                                now: Self.now, minInterval: Self.minInterval, inFlight: inFlight))

        // /a completes; the stale-cwd re-enqueue now asks for /b → spawns for /b
        // (a new cwd) even within the min-interval, so the latest cwd wins
        inFlight = false
        #expect(GitRefreshPolicy.shouldRefresh(cwd: "/b", lastRanCwd: lastRanCwd, lastRanAt: lastRanAt,
                                               now: Self.now, minInterval: Self.minInterval, inFlight: inFlight))
    }
}

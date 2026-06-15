import Foundation
import Testing
@testable import agtCore

@MainActor
struct SessionTests {
    @Test(arguments: [
        ("/Users/umputun/dev/foo", "foo"),
        ("/", "/"),
        ("/a/b/", "b"),
        ("/Users/umputun", "umputun"),
        ("", "~"),
    ])
    func basenameDerivation(input: String, expected: String) {
        let session = Session(initialCwd: input)
        #expect(session.displayName == expected)
    }

    @Test func currentCwdOverridesInitialForDisplay() {
        let session = Session(initialCwd: "/start")
        #expect(session.displayName == "start")
        session.currentCwd = "/Users/umputun/dev/bar"
        #expect(session.displayName == "bar")
    }

    @Test func customNameOverridesAuto() {
        let session = Session(initialCwd: "/Users/umputun/dev/foo")
        #expect(session.displayName == "foo")
        session.customName = "build"
        #expect(session.displayName == "build")
    }

    @Test func clearingCustomNameRestoresAuto() {
        let session = Session(initialCwd: "/Users/umputun/dev/foo", customName: "build")
        #expect(session.displayName == "build")
        session.customName = nil
        #expect(session.displayName == "foo")
    }

    @Test func emptyCustomNameFallsBackToAuto() {
        let session = Session(initialCwd: "/Users/umputun/dev/foo", customName: "")
        #expect(session.displayName == "foo")
    }

    @Test func whitespaceOnlyCustomNameFallsBackToAuto() {
        // A whitespace-only customName can only reach displayName via a hand-edited
        // snapshot (renameSession clears blanks to nil); it's trimmed and falls back
        // to the basename, matching renameSession's behavior.
        let session = Session(initialCwd: "/Users/umputun/dev/foo", customName: "   \t")
        #expect(session.displayName == "foo")
    }

    @Test func paddedCustomNameDisplaysTrimmed() {
        // A padded customName (e.g. from a hand-edited snapshot) displays trimmed,
        // matching the "trimmed before use" contract.
        let session = Session(initialCwd: "/Users/umputun/dev/foo", customName: "  build  ")
        #expect(session.displayName == "build")
    }
}

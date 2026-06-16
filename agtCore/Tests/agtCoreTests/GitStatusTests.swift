import Foundation
import Testing
@testable import agtCore

struct GitStatusTests {
    // MARK: parse fixtures

    @Test func cleanInSync() {
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.branch == "main")
        #expect(status.detachedSHA == nil)
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 0)
        #expect(status.behind == 0)
        #expect(status.dirty == 0)
        #expect(status.worktree == nil)
    }

    @Test func aheadOnly() {
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head feature
        # branch.upstream origin/feature
        # branch.ab +5 -0
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.ahead == 5)
        #expect(status.behind == 0)
        #expect(status.dirty == 0)
    }

    @Test func behindOnly() {
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -2
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.ahead == 0)
        #expect(status.behind == 2)
    }

    @Test func aheadAndBehind() {
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +5 -2
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.ahead == 5)
        #expect(status.behind == 2)
    }

    @Test func dirtyMixedEntries() {
        // a 2 (rename) line ends with two tab-separated paths; the parser counts by
        // leading token, so embedded paths/spaces must not throw off the count.
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0
        1 .M N... 100644 100644 100644 aaaa bbbb modified.txt
        2 R. N... 100644 100644 100644 cccc dddd R100 new name.txt\told name.txt
        u UU N... 100644 100644 100644 100644 eeee ffff gggg conflicted.txt
        ? untracked.txt
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.dirty == 4)
    }

    @Test func noUpstreamStillRepo() {
        // no branch.ab line at all → ahead/behind 0, still a valid repo (branch set)
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.branch == "main")
        #expect(status.detachedSHA == nil)
        #expect(status.upstream == nil)
        #expect(status.ahead == 0)
        #expect(status.behind == 0)
    }

    @Test func detachedHead() {
        let output = """
        # branch.oid abcdef1234567890abcdef1234567890abcdef12
        # branch.head (detached)
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.branch == nil)
        #expect(status.detachedSHA == "abcdef1")
        #expect(status.ahead == 0)
        #expect(status.behind == 0)
    }

    @Test func initialCommitIsNotDetached() {
        // a fresh repo with no commits emits a normal branch.head plus an (initial)
        // oid; (initial) must not be treated as a detached SHA.
        let output = """
        # branch.oid (initial)
        # branch.head main
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.branch == "main")
        #expect(status.detachedSHA == nil)
    }

    @Test func linkedWorktreeGitDir() {
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: "/Users/u/proj/.git/worktrees/feature-x")
        #expect(status.worktree == "feature-x")
    }

    @Test func mainWorktreeGitDir() {
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: "/Users/u/proj/.git")
        #expect(status.worktree == nil)
    }

    @Test func relativeGitDirIsMainWorktree() {
        let output = """
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.worktree == nil)
    }

    @Test func worktreesSubstringElsewhereDoesNotFalsePositive() {
        // a path that merely contains "worktrees/" mid-path (not as the trailing
        // segment) must not be detected as a linked worktree.
        let output = "# branch.head main"
        let status = GitStatus.parse(porcelainV2: output, gitDir: "/Users/u/worktrees/proj/.git")
        #expect(status.worktree == nil)
    }

    @Test func nilGitDirIsMainWorktree() {
        let status = GitStatus.parse(porcelainV2: "# branch.head main", gitDir: nil)
        #expect(status.worktree == nil)
    }

    @Test func trailingNewlineDoesNotAddEntry() {
        // git's output ends with a trailing newline; the empty final line must not be
        // miscounted as a dirty entry.
        let output = "# branch.head main\n1 .M N... 100644 100644 100644 aaaa bbbb modified.txt\n"
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.branch == "main")
        #expect(status.dirty == 1)
    }

    @Test func blankEntryLinesIgnored() {
        // interior blank lines (omitted by the split) must not count toward dirty.
        let output = "# branch.head main\n\n\n? untracked.txt\n"
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.dirty == 1)
    }

    @Test func crlfLineEndingsTolerated() {
        // CRLF input must not pollute the branch name with a trailing \r or break
        // entry counting.
        let output = "# branch.head main\r\n# branch.ab +1 -0\r\n1 .M N... 100644 100644 100644 aaaa bbbb f.txt\r\n"
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.branch == "main")
        #expect(status.ahead == 1)
        #expect(status.dirty == 1)
    }

    @Test func detachedWithAheadBehind() {
        // a detached HEAD can still report ahead/behind when an upstream is tracked;
        // the SHA and the divergence counts must coexist.
        let output = """
        # branch.oid abcdef1234567890abcdef1234567890abcdef12
        # branch.head (detached)
        # branch.upstream origin/main
        # branch.ab +3 -4
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.branch == nil)
        #expect(status.detachedSHA == "abcdef1")
        #expect(status.ahead == 3)
        #expect(status.behind == 4)
    }

    @Test func detachedWithDirty() {
        // a detached HEAD with uncommitted changes counts dirty entries normally.
        let output = """
        # branch.oid abcdef1234567890abcdef1234567890abcdef12
        # branch.head (detached)
        1 .M N... 100644 100644 100644 aaaa bbbb modified.txt
        ? untracked.txt
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.branch == nil)
        #expect(status.detachedSHA == "abcdef1")
        #expect(status.dirty == 2)
    }

    // MARK: compact formatting

    @Test(arguments: [
        (GitStatus(branch: "main"), ""),
        (GitStatus(branch: "main", ahead: 5), "↑5"),
        (GitStatus(branch: "main", behind: 2), "↓2"),
        (GitStatus(branch: "main", dirty: 3), "*3"),
        (GitStatus(branch: "main", ahead: 5, behind: 2), "↑5 ↓2"),
        (GitStatus(branch: "main", ahead: 5, behind: 2, dirty: 1), "↑5 ↓2 *1"),
    ])
    func compactFormatting(status: GitStatus, expected: String) {
        #expect(status.compact == expected)
    }

    // MARK: branchDisplay formatting

    @Test func branchDisplayOnBranch() {
        #expect(GitStatus(branch: "main").branchDisplay == "main")
    }

    @Test func branchDisplayDetached() {
        #expect(GitStatus(detachedSHA: "abcdef1").branchDisplay == "detached @ abcdef1")
    }

    @Test func unsignedAheadBehindTokenIgnored() {
        // a token without a +/- sign matches neither ahead nor behind and is dropped,
        // leaving both at their defaults (0).
        let output = """
        # branch.head main
        # branch.upstream origin/main
        # branch.ab 5 2
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.ahead == 0)
        #expect(status.behind == 0)
    }

    @Test func malformedAheadBehindTokenParsesZero() {
        // a signed but non-numeric token parses to 0 rather than crashing or carrying
        // garbage; the well-formed sibling token still parses normally.
        let output = """
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +x -2
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.ahead == 0)
        #expect(status.behind == 2)
    }

    @Test func behindParsedPositive() {
        // porcelain v2 emits behind as a negatively-signed token; the sign is
        // stripped and stored as a non-negative count.
        let output = """
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -7
        """
        let status = GitStatus.parse(porcelainV2: output, gitDir: ".git")
        #expect(status.behind == 7)
        #expect(status.behind >= 0)
    }
}

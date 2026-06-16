import Foundation

/// The git status of a session's working directory, parsed from
/// `git status --porcelain=v2 --branch` plus `git rev-parse --git-dir`.
///
/// A plain value type: `Equatable` so the service can equality-gate the
/// `@Observable` write, `Sendable` so the off-main worker can compute it and hand
/// it to the main actor. Every member must stay value/`Sendable` — adding a
/// reference or closure property would break the cross-actor design at compile time.
///
/// Invariant: exactly one of `branch`/`detachedSHA` is set (`branch == nil ⟺
/// detachedSHA != nil`).
public struct GitStatus: Equatable, Sendable {
    /// The current branch name, or nil when HEAD is detached.
    public var branch: String?
    /// The short SHA of a detached HEAD, or nil when on a branch.
    public var detachedSHA: String?
    /// The upstream ref (e.g. `origin/main`), or nil when no upstream is set.
    public var upstream: String?
    /// Commits ahead of upstream (0 when no upstream or in sync).
    public var ahead: Int
    /// Commits behind upstream (0 when no upstream or in sync); always non-negative.
    public var behind: Int
    /// Count of dirty entries (tracked changes + untracked); 0 when clean.
    public var dirty: Int
    /// The linked-worktree name, or nil for the main work tree.
    public var worktree: String?

    public init(branch: String? = nil, detachedSHA: String? = nil, upstream: String? = nil,
                ahead: Int = 0, behind: Int = 0, dirty: Int = 0, worktree: String? = nil) {
        self.branch = branch
        self.detachedSHA = detachedSHA
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.dirty = dirty
        self.worktree = worktree
    }

    /// Parses `git status --porcelain=v2 --branch` output plus an optional
    /// `git rev-parse --git-dir` path into a `GitStatus`.
    ///
    /// Pure and total — never throws, never returns nil. The "is this a repo?"
    /// decision lives in the service (a non-zero git exit → `gitStatus = nil`);
    /// `parse` is only ever called with real status output.
    ///
    /// Header lines: `# branch.head <name>` sets `branch` unless the value is the
    /// literal `(detached)`, in which case `branch` stays nil and `detachedSHA`
    /// comes from `# branch.oid <sha>` (short-formed). A `(initial)` oid (unborn
    /// branch / no commits) is NOT a detached SHA — only the literal `(detached)`
    /// head value sets it. `# branch.ab +<ahead> -<behind>` fills ahead/behind with
    /// the sign stripped (behind is stored as `abs`); its absence means no upstream
    /// (ahead/behind both 0), not non-git. Entry lines (leading `1`/`2`/`u`/`?`)
    /// each count one toward `dirty`, regardless of per-line field shape.
    public static func parse(porcelainV2 output: String, gitDir: String?) -> GitStatus {
        var status = GitStatus()
        var oid: String?
        var headIsDetached = false

        // split on any newline (LF/CRLF/CR) so CRLF input doesn't leave a stray \r on
        // header values; empty subsequences (blank/trailing lines) are omitted.
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") {
                status.applyHeader(line: String(line), oid: &oid, headIsDetached: &headIsDetached)
                continue
            }
            // any non-# line is an entry (changed/renamed/unmerged/untracked); count it
            let leading = line.first
            if leading == "1" || leading == "2" || leading == "u" || leading == "?" {
                status.dirty += 1
            }
        }

        if headIsDetached, let oid, oid != "(initial)" {
            status.branch = nil
            status.detachedSHA = GitStatus.shortSHA(oid)
        }

        status.worktree = GitStatus.worktreeName(fromGitDir: gitDir)
        return status
    }

    /// Applies a single `# …` header line to the in-progress status, tracking the
    /// raw oid and whether the head value was the literal `(detached)`.
    private mutating func applyHeader(line: String, oid: inout String?, headIsDetached: inout Bool) {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 2 else { return }
        switch fields[1] {
        case "branch.head":
            guard fields.count >= 3 else { return }
            if fields[2] == "(detached)" {
                headIsDetached = true
            } else {
                branch = fields[2]
            }
        case "branch.oid":
            if fields.count >= 3 { oid = fields[2] }
        case "branch.upstream":
            if fields.count >= 3 { upstream = fields[2] }
        case "branch.ab":
            applyAheadBehind(fields: fields)
        default:
            break
        }
    }

    /// Parses the `# branch.ab +<ahead> -<behind>` tokens, stripping signs so
    /// `behind` is stored as a non-negative count.
    private mutating func applyAheadBehind(fields: [String]) {
        for token in fields.dropFirst(2) {
            let signed = token.hasPrefix("+") || token.hasPrefix("-")
            let magnitude = abs(Int(token.dropFirst(signed ? 1 : 0)) ?? 0)
            if token.hasPrefix("+") { ahead = magnitude }
            if token.hasPrefix("-") { behind = magnitude }
        }
    }

    /// Shortens an oid to a 7-char prefix (git's default short length).
    private static func shortSHA(_ oid: String) -> String {
        String(oid.prefix(7))
    }

    /// Extracts a linked-worktree name from a git-dir path of the form
    /// `…/worktrees/<name>`, matching the trailing segment so an unrelated path
    /// containing `worktrees/` elsewhere can't false-positive. Anything else
    /// (e.g. ending in `.git`) → nil (main work tree).
    private static func worktreeName(fromGitDir gitDir: String?) -> String? {
        guard let gitDir else { return nil }
        let trimmed = gitDir.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 2, components[components.count - 2] == "worktrees" else { return nil }
        return components[components.count - 1]
    }

    /// The sidebar tokens: `↑<ahead>` when ahead, `↓<behind>` when behind,
    /// `*<dirty>` (the conventional git "dirty" marker plus the changed-file count)
    /// when dirty, space-joined in a fixed order; empty when clean and in sync. No
    /// branch name — the row already shows the session name.
    public var compact: String {
        var tokens: [String] = []
        if ahead > 0 { tokens.append("↑\(ahead)") }
        if behind > 0 { tokens.append("↓\(behind)") }
        if dirty > 0 { tokens.append("*\(dirty)") }
        return tokens.joined(separator: " ")
    }

    /// The branch label for the detail pill: the branch name, or
    /// `detached @ <shortsha>` for a detached HEAD.
    public var branchDisplay: String {
        if let branch { return branch }
        if let detachedSHA { return "detached @ \(detachedSHA)" }
        return ""
    }
}

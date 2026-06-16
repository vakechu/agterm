import Foundation

/// The persisted form of the whole app state: a plain value tree that mirrors the
/// `@MainActor` model but carries no live `Session`/`Workspace` references.
///
/// `Codable` for JSON, `Equatable` so tests can assert round-trips, `Sendable` so
/// it can cross the actor boundary — the snapshot is built on `@MainActor` and
/// handed to the file writer as a value.
public struct Snapshot: Codable, Equatable, Sendable {
    /// Bumped when the on-disk shape changes; a mismatch makes the loader start fresh.
    public static let currentVersion = 1

    public var version: Int
    public var selectedSessionID: UUID?
    public var workspaces: [WorkspaceSnapshot]
    /// Whether the bottom status bar is hidden. Optional so a pre-existing
    /// `workspaces.json` written before this field decodes (as nil → shown)
    /// instead of failing the whole load.
    public var statusBarHidden: Bool?

    public init(version: Int = Snapshot.currentVersion, selectedSessionID: UUID? = nil,
                workspaces: [WorkspaceSnapshot] = [], statusBarHidden: Bool? = nil) {
        self.version = version
        self.selectedSessionID = selectedSessionID
        self.workspaces = workspaces
        self.statusBarHidden = statusBarHidden
    }
}

/// One persisted workspace: its identity, name, and ordered sessions.
public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var sessions: [SessionSnapshot]

    public init(id: UUID, name: String, sessions: [SessionSnapshot]) {
        self.id = id
        self.name = name
        self.sessions = sessions
    }
}

/// One persisted session: its identity, optional custom name, and the working
/// directory to re-spawn a fresh shell in. `cwd` is the live `currentCwd`, or the
/// `initialCwd` when no PWD report has arrived yet.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var customName: String?
    public var cwd: String

    public init(id: UUID, customName: String?, cwd: String) {
        self.id = id
        self.customName = customName
        self.cwd = cwd
    }
}

import Foundation

/// A user-named group of sessions (e.g. "work", "personal"). A value type with
/// a stable UUID identity; its `sessions` array holds `Session` references.
@MainActor
public struct Workspace: Identifiable {
    public let id: UUID
    public var name: String
    public var sessions: [Session]

    public init(name: String, sessions: [Session] = []) {
        id = UUID()
        self.name = name
        self.sessions = sessions
    }

    public init(id: UUID, name: String, sessions: [Session] = []) {
        self.id = id
        self.name = name
        self.sessions = sessions
    }
}

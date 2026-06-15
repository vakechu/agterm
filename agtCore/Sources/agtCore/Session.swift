import Foundation
import Observation

/// One shell, backed by a single libghostty surface.
///
/// `@MainActor` (so it's implicitly `Sendable` via isolation — never made an
/// `actor`). The `surface` slot is `@ObservationIgnored` so assigning the
/// lazily-created NSView never churns observation; only `customName`/`currentCwd`
/// are observed, so the sidebar refreshes when a rename or PWD report lands.
@Observable
@MainActor
public final class Session: Identifiable {
    public let id: UUID
    public var customName: String?
    /// The live working directory from the latest OSC 7 / PWD report. Observed, so
    /// the sidebar row refreshes when it changes. It is captured by `snapshot()`
    /// and so persisted on quit and on structural mutations, but a bare `cd` does
    /// not trigger a save (OSC 7 fires constantly), so a crash loses only cwd
    /// changes since the last structural mutation.
    public var currentCwd: String?
    public let initialCwd: String

    /// The app-side surface (a `GhosttySurfaceView`). Lazily created on first
    /// display and owned here so it survives sidebar/detail view churn.
    @ObservationIgnored public var surface: (any TerminalSurface)?

    public init(id: UUID = UUID(), initialCwd: String, customName: String? = nil) {
        self.id = id
        self.initialCwd = initialCwd
        self.customName = customName
    }

    /// The sidebar label: a non-blank `customName` wins; otherwise the basename
    /// of the live cwd (falling back to `initialCwd`).
    ///
    /// `customName` is trimmed before use, so a whitespace-only value falls back
    /// to the basename — matching `AppStore.renameSession`, which clears a blank
    /// name to nil. (A whitespace-only `customName` can only reach here via a
    /// hand-edited snapshot; `renameSession` never stores one.)
    ///
    /// Basename pins: root `/` → `/` (`lastPathComponent` already returns this);
    /// a trailing slash is ignored (`/a/b/` → `b`); an empty path → `~` (no
    /// sensible component exists, so we show the home shorthand).
    public var displayName: String {
        if let trimmed = customName?.trimmedOrNil { return trimmed }
        let path = currentCwd ?? initialCwd
        if path.isEmpty { return "~" }
        return (path as NSString).lastPathComponent
    }
}

extension String {
    /// The string trimmed of leading/trailing whitespace and newlines, or nil if
    /// the result is empty. The single normalizer for the rename/displayName
    /// "blank after trim" rule.
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

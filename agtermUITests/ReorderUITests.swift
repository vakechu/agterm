import XCTest

/// Real UI tests for drag-and-drop reorder within the sidebar. These launch the
/// actual app and drive the `NSOutlineView` through the accessibility API, the
/// coverage the host-free `agtermCore` unit tests cannot reach (the drag-drop
/// index handling lives in `WorkspaceSidebar.Coordinator`).
@MainActor
final class ReorderUITests: XCTestCase {
    private var app: XCUIApplication!
    private var stateDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        // hermetic state: a fresh temp dir per test so the app seeds exactly one
        // "workspace 1" + one session, and we never touch the real workspaces.json.
        stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agterm-uitest-\(UUID().uuidString)", isDirectory: true)
        app = XCUIApplication()
        app.launchEnvironment["AGTERM_STATE_DIR"] = stateDir.path
        app.launchForUITest()
    }

    override func tearDown() async throws {
        app?.terminate()
        if let stateDir { try? FileManager.default.removeItem(at: stateDir) }
    }

    // Drag a session UP onto a higher sibling and confirm the persisted order changed through the
    // full sidebar drop path (validateDrop → acceptDrop → moveSession). Three sessions are renamed
    // aaa/bbb/ccc so the persisted `customName` order is an unambiguous oracle. Dropping ccc ON
    // aaa's row inserts ccc just after aaa: [aaa, bbb, ccc] → [aaa, ccc, bbb].
    func testReorderSessionUp() throws {
        seedSessions(["aaa", "bbb", "ccc"])
        dragRow(named: "ccc", onto: "aaa")
        XCTAssertTrue(pollSessionNames(["aaa", "ccc", "bbb"], timeout: 10),
                      "dragging ccc up onto aaa should reorder to [aaa, ccc, bbb]")
    }

    // Drag a session DOWN onto a lower sibling. Dropping bbb ON ccc's row inserts bbb just after
    // ccc: [aaa, bbb, ccc] → [aaa, ccc, bbb]. The downward path exercises the same-workspace
    // `childIndex - 1` post-removal adjustment in `acceptDrop` (sourceIndex 1 < dropChildIndex 3)
    // that the up-move does not.
    func testReorderSessionDown() throws {
        seedSessions(["aaa", "bbb", "ccc"])
        dragRow(named: "bbb", onto: "ccc")
        XCTAssertTrue(pollSessionNames(["aaa", "ccc", "bbb"], timeout: 10),
                      "dragging bbb down onto ccc should reorder to [aaa, ccc, bbb]")
    }

    // Drag a session DOWN onto a MIDDLE row (not the last). With four sessions [aaa, bbb, ccc, ddd],
    // dragging aaa onto ccc's row inserts aaa just after ccc → [bbb, ccc, aaa, ddd]. This discriminates
    // the same-workspace downward `childIndex - 1` post-removal adjustment: WITH it the session lands at
    // index 2 ([bbb, ccc, aaa, ddd]); WITHOUT it the append-clamp would push it to the END
    // ([bbb, ccc, ddd, aaa]) — the two outcomes differ only because the drop is NOT onto the last row.
    func testReorderSessionDownPastMiddle() throws {
        seedSessions(["aaa", "bbb", "ccc", "ddd"])
        dragRow(named: "aaa", onto: "ccc")
        XCTAssertTrue(pollSessionNames(["bbb", "ccc", "aaa", "ddd"], timeout: 10),
                      "dragging aaa down onto the middle row ccc should land it between ccc and ddd")
    }

    // Drag a workspace UP above a higher sibling and confirm the persisted order changed through the
    // full sidebar drop path (validateDrop → acceptDrop → moveWorkspace). Three workspaces are created
    // (workspace 1/2/3). Dropping "workspace 3" near the TOP edge of "workspace 1" lands a top-level
    // between-rows drop above it: [workspace 1, workspace 2, workspace 3] → [workspace 3, workspace 1, workspace 2].
    func testReorderWorkspace() throws {
        seedThreeWorkspaces()
        dragWorkspaceRow(named: "workspace 3", toTopOf: "workspace 1")
        XCTAssertTrue(pollWorkspaceNames(["workspace 3", "workspace 1", "workspace 2"], timeout: 10),
                      "dragging workspace 3 above workspace 1 should reorder to [workspace 3, workspace 1, workspace 2]")
    }

    // Drop a workspace onto a SESSION row that belongs to another workspace — the realistic case the
    // edge-sliver test misses. With workspaces expanded (each holding sessions, like the real app), the
    // space between workspace rows is filled with session rows, so a dragged workspace lands ON a session
    // (or workspace) row, which AppKit proposes as `item != nil`. The original `guard item == nil` rejected
    // every such drop (the reported "can't drag workspaces" bug). Dropping workspace 3 onto workspace 1's
    // session row reorders it just after its owning workspace: [w1, w2, w3] → [w1, w3, w2].
    func testReorderWorkspaceOntoSessionRow() throws {
        seedThreeWorkspaces() // workspace 1 keeps the seeded session; 2 and 3 are empty
        dragWorkspaceOntoSessionRow(named: "workspace 3")
        XCTAssertTrue(pollWorkspaceNames(["workspace 1", "workspace 3", "workspace 2"], timeout: 10),
                      "dropping workspace 3 onto workspace 1's session row should land it after workspace 1 → [w1, w3, w2]")
    }

    // MARK: - Fixture

    /// Renames the seeded session to `names[0]` and adds one more renamed row per remaining name,
    /// leaving the single workspace holding `names` in order. Each rename targets the only freshly-added
    /// (default-named) row, which stays unique at that step. Callers pass [aaa, bbb, ccc] (three) or
    /// [aaa, bbb, ccc, ddd] (four, so a downward drag can target a MIDDLE row rather than the last).
    private func seedSessions(_ names: [String]) {
        XCTAssertTrue(sessionRow().waitForExistence(timeout: 20), "seeded session should exist")
        let defaultName = (sessionRow().value as? String) ?? ""
        XCTAssertFalse(defaultName.isEmpty, "seeded session should expose a default name")
        for (i, name) in names.enumerated() {
            if i > 0 { addSession() }
            rename(rowNamed: defaultName, to: name)
        }
        XCTAssertTrue(pollSessionNames(names, timeout: 10),
                      "the renamed sessions should persist in creation order")
    }

    /// Adds two more workspaces to the seeded one, leaving the tree holding
    /// [workspace 1, workspace 2, workspace 3] (workspace 1 keeps the seeded session; 2 and 3 are empty).
    private func seedThreeWorkspaces() {
        XCTAssertTrue(app.staticTexts["workspace 1"].waitForExistence(timeout: 20), "seeded workspace should exist")
        addWorkspace()
        addWorkspace()
        XCTAssertTrue(pollWorkspaceNames(["workspace 1", "workspace 2", "workspace 3"], timeout: 10),
                      "the three workspaces should persist in creation order")
    }

    // MARK: - Helpers

    /// The (single, seeded) session row, matched by its stable accessibility identifier.
    private func sessionRow() -> XCUIElement { app.staticTexts["session-row"] }

    /// A session row matched by its displayed name (lands in the StaticText `value`). Constrained
    /// to the `session-row` identifier so it never matches the window title (which carries the same
    /// cwd-basename text).
    private func sessionRow(named name: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "session-row", name))
            .firstMatch
    }

    /// A workspace row matched by its displayed name (lands in the StaticText `value`), constrained
    /// to the `workspace-row` identifier.
    private func workspaceRow(named name: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "workspace-row", name))
            .firstMatch
    }

    /// Drags the workspace row named `source` to the TOP edge of the row named `target`. Aiming the
    /// drop at the top sliver of the target lands a top-level between-rows drop ABOVE it (the only
    /// valid workspace-reorder slot — `proposedItem == nil`), so the dragged workspace inserts just
    /// before the target. Same gesture mechanics as `dragRow`: select the source first (the outline
    /// only drags the selected row), then a mouse-native coordinate drag.
    private func dragWorkspaceRow(named source: String, toTopOf target: String) {
        let from = workspaceRow(named: source)
        let to = workspaceRow(named: target)
        XCTAssertTrue(from.waitForHittable(timeout: 10), "\(source) row should be hittable to drag")
        XCTAssertTrue(to.waitForHittable(timeout: 10), "\(target) row should be hittable as a drop target")
        from.click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let start = from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // the top sliver of the target → NSOutlineView proposes a drop above it at the top level.
        let end = to.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        start.click(forDuration: 0.7, thenDragTo: end, withVelocity: 180, thenHoldForDuration: 0.25)
    }

    /// Drags the workspace row named `source` onto the CENTER of the seeded session row (which belongs to
    /// workspace 1) — so the drop lands ON a session row (`item != nil`), the realistic case where a
    /// workspace reorder must still work. Same gesture mechanics as `dragWorkspaceRow(named:toTopOf:)`.
    private func dragWorkspaceOntoSessionRow(named source: String) {
        let from = workspaceRow(named: source)
        let to = sessionRow()
        XCTAssertTrue(from.waitForHittable(timeout: 10), "\(source) row should be hittable to drag")
        XCTAssertTrue(to.waitForHittable(timeout: 10), "the session row should be hittable as a drop target")
        from.click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let start = from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = to.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.7, thenDragTo: end, withVelocity: 180, thenHoldForDuration: 0.25)
    }

    /// Adds a new (empty) workspace via the bottom-bar add-workspace button.
    private func addWorkspace() {
        app.buttons["New Workspace"].click()
    }

    /// Drags the session row named `source` onto the row named `target`. Two details make the
    /// NSOutlineView drag deliver to the drop delegate reliably:
    /// 1. drag via `coordinate(withNormalizedOffset:)`, NOT element-to-element — the AX element is
    ///    the recycled `NSTextField` inside the row, while the drag tracking lives in the outline,
    ///    so a coordinate drag targets the outline machinery directly;
    /// 2. use the mouse-native `click(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`
    ///    (with a final hold), NOT the touch `press(...)`.
    private func dragRow(named source: String, onto target: String) {
        let from = sessionRow(named: source)
        let to = sessionRow(named: target)
        XCTAssertTrue(from.waitForHittable(timeout: 10), "\(source) row should be hittable to drag")
        XCTAssertTrue(to.waitForHittable(timeout: 10), "\(target) row should be hittable as a drop target")
        // select the source row first: the outline only begins a drag from the selected row, so an
        // unselected source (e.g. a middle row that wasn't the last one touched) never starts a drag.
        from.click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let start = from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = to.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.7, thenDragTo: end, withVelocity: 180, thenHoldForDuration: 0.25)
    }

    /// Adds a new session to the current workspace via the bottom-bar add-session menu.
    private func addSession() {
        let add = app.descendants(matching: .any).matching(identifier: "add-session").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "bottom-bar add-session menu should exist")
        add.click()
        let newItem = presentedMenuItem("New Session")
        XCTAssertTrue(newItem.waitForExistence(timeout: 5), "New Session menu item should appear")
        newItem.click()
    }

    /// Renames the session row currently showing `currentName` to `newName`. Uses a double-click
    /// to start the inline rename (the outline's `doubleAction`) — far more reliable than the
    /// context-menu path when a bottom-bar menu was just dismissed. `currentName` must be unique
    /// among the rows at the time of the call.
    private func rename(rowNamed currentName: String, to newName: String) {
        let row = sessionRow(named: currentName)
        XCTAssertTrue(row.waitForHittable(timeout: 10), "a session row named \(currentName) to rename should be hittable")
        let field = app.descendants(matching: .any).matching(identifier: "edit-field").firstMatch
        var editing = false
        for _ in 0..<5 {
            row.doubleClick()
            if field.waitForExistence(timeout: 2) { editing = true; break }
        }
        XCTAssertTrue(editing, "rename did not enter edit mode for \(currentName) (field never appeared)")
        app.typeKey("a", modifierFlags: .command)
        app.typeText("\(newName)\r")
        XCTAssertTrue(sessionRow(named: newName).waitForExistence(timeout: 5), "renamed session row should appear")
    }

    /// The on-screen (hittable) menu item with `title`, filtering out the closed menu-bar twin.
    private func presentedMenuItem(_ title: String, timeout: TimeInterval = 5) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let matches = app.menuItems.matching(identifier: title).allElementsBoundByIndex
            if let hit = matches.first(where: { $0.exists && $0.isHittable }) { return hit }
            usleep(150_000)
        }
        return app.menuItems[title].firstMatch
    }

    /// Polls the hermetic snapshot file until the (single seeded workspace's) session
    /// `customName`s equal `expected`, in order.
    private func pollSessionNames(_ expected: [String], timeout: TimeInterval) -> Bool {
        stateDir.pollSnapshot(equals: expected, timeout: timeout) { obj in
            guard let workspaces = obj["workspaces"] as? [[String: Any]],
                  let sessions = workspaces.first?["sessions"] as? [[String: Any]] else { return nil }
            return sessions.compactMap { $0["customName"] as? String }
        }
    }

    /// Polls the hermetic snapshot file until the workspace `name`s equal `expected`, in order.
    private func pollWorkspaceNames(_ expected: [String], timeout: TimeInterval) -> Bool {
        stateDir.pollSnapshot(equals: expected, timeout: timeout) { obj in
            guard let workspaces = obj["workspaces"] as? [[String: Any]] else { return nil }
            return workspaces.compactMap { $0["name"] as? String }
        }
    }
}

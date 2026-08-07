import Testing
@testable import SeeleseekCore
@testable import seeleseek

/// The status-bar menu decides between three responses to a tick: do nothing,
/// retitle the existing rows, or tear the menu down and rebuild it. That
/// decision is `MenuBarModel` equality plus `shape` equality, and getting it
/// wrong is invisible in review — too eager and the menu flickers under the
/// cursor mid-interaction, too lazy and it displays stale numbers.
@Suite("Menu bar model")
struct MenuBarModelTests {

    private func model(
        status: ConnectionStatus = .connected,
        username: String? = "seele",
        downSpeed: Int64 = 0,
        upSpeed: Int64 = 0,
        activeDown: Int = 0,
        activeUp: Int = 0,
        queued: Int = 0
    ) -> MenuBarModel {
        MenuBarModel(
            status: status,
            username: username,
            downSpeed: downSpeed,
            upSpeed: upSpeed,
            activeDown: activeDown,
            activeUp: activeUp,
            queued: queued
        )
    }

    // MARK: - Retitle in place

    @Test("Speed changes keep the same shape, so the menu is retitled not rebuilt")
    func speedChangeKeepsShape() {
        let before = model(downSpeed: 1_000, activeDown: 2)
        let after = model(downSpeed: 5_000, activeDown: 2)

        #expect(before != after)            // something to redraw
        #expect(before.shape == after.shape)  // but no row appeared or vanished
    }

    @Test("Counts changing without crossing zero keeps the same shape")
    func countChangeKeepsShape() {
        let before = model(activeDown: 1, activeUp: 3, queued: 2)
        let after = model(activeDown: 7, activeUp: 1, queued: 9)

        #expect(before != after)
        #expect(before.shape == after.shape)
    }

    @Test("An identical snapshot is skipped entirely")
    func identicalSnapshotIsEqual() {
        #expect(model(downSpeed: 42, activeDown: 1) == model(downSpeed: 42, activeDown: 1))
    }

    // MARK: - Rebuild

    @Test("A count crossing zero adds or removes its row")
    func crossingZeroChangesShape() {
        #expect(model(activeDown: 0).shape != model(activeDown: 1).shape)
        #expect(model(activeUp: 0).shape != model(activeUp: 1).shape)
        #expect(model(queued: 0).shape != model(queued: 1).shape)
    }

    @Test("Disconnecting removes the speeds row")
    func disconnectingChangesShape() {
        let connected = model(status: .connected)
        let dropped = model(status: .disconnected, username: nil)

        #expect(connected.shape.speeds)
        #expect(!dropped.shape.speeds)
        #expect(connected.shape != dropped.shape)
    }

    @Test("Speeds show only while connected, whatever the numbers say")
    func speedsRequireConnection() {
        #expect(!model(status: .connecting, username: nil, downSpeed: 9_000).shape.speeds)
        #expect(!model(status: .reconnecting, username: nil, downSpeed: 9_000).shape.speeds)
        #expect(!model(status: .error, username: nil, downSpeed: 9_000).shape.speeds)
        #expect(model(status: .connected, downSpeed: 0).shape.speeds)
    }

    /// The header grows a second line when a username is known. That changes
    /// the row's height, so it has to force a rebuild rather than a retitle —
    /// this is the one shape input that is not a row appearing or vanishing.
    @Test("Learning the username re-lays-out the header")
    func usernameArrivingChangesShape() {
        let anonymous = model(username: nil)
        let named = model(username: "seele")

        #expect(!anonymous.shape.namedHeader)
        #expect(named.shape.namedHeader)
        #expect(anonymous.shape != named.shape)
    }

    @Test("A username while disconnected does not produce a two-line header")
    func usernameWithoutConnectionIsNotNamed() {
        #expect(!model(status: .disconnected, username: "seele").shape.namedHeader)
        #expect(!model(status: .connecting, username: "seele").shape.namedHeader)
    }

    @Test("Renaming redraws but does not relayout")
    func renameKeepsShape() {
        let before = model(username: "seele")
        let after = model(username: "lilith")

        #expect(before != after)
        #expect(before.shape == after.shape)
    }
}

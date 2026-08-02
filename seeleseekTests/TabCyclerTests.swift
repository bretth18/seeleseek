import Testing
@testable import seeleseek

/// The menu commands (Show Next/Previous Tab) wrap; arrow keys inside a
/// tab bar clamp. Both must survive empty and out-of-range inputs, which
/// occur when the last closable tab is removed mid-update.
@Suite("TabCycler")
struct TabCyclerTests {

    @Test("Wrapped next advances and wraps at the end")
    func wrappedNext() {
        #expect(TabCycler.wrappedNext(0, count: 3) == 1)
        #expect(TabCycler.wrappedNext(1, count: 3) == 2)
        #expect(TabCycler.wrappedNext(2, count: 3) == 0)
    }

    @Test("Wrapped previous retreats and wraps at the start")
    func wrappedPrevious() {
        #expect(TabCycler.wrappedPrevious(2, count: 3) == 1)
        #expect(TabCycler.wrappedPrevious(1, count: 3) == 0)
        #expect(TabCycler.wrappedPrevious(0, count: 3) == 2)
    }

    @Test("Wrapped next from the no-selection sentinel lands on the first tab")
    func wrappedNextFromSentinel() {
        #expect(TabCycler.wrappedNext(-1, count: 4) == 0)
    }

    @Test("Clamped traversal stops at the ends")
    func clampedStopsAtEnds() {
        #expect(TabCycler.clampedNext(0, count: 3) == 1)
        #expect(TabCycler.clampedNext(2, count: 3) == 2)
        #expect(TabCycler.clampedPrevious(2, count: 3) == 1)
        #expect(TabCycler.clampedPrevious(0, count: 3) == 0)
    }

    @Test("Out-of-range indices clamp into bounds")
    func clampedOutOfRange() {
        #expect(TabCycler.clampedNext(7, count: 3) == 2)
        #expect(TabCycler.clampedPrevious(7, count: 3) == 1)
        #expect(TabCycler.clampedPrevious(-3, count: 3) == 0)
    }

    @Test("Zero count never traps or returns a negative index")
    func zeroCount() {
        #expect(TabCycler.wrappedNext(0, count: 0) == 0)
        #expect(TabCycler.wrappedPrevious(0, count: 0) == 0)
        #expect(TabCycler.clampedNext(0, count: 0) == 0)
        #expect(TabCycler.clampedPrevious(0, count: 0) == 0)
    }

    @Test("Single tab is a fixed point for every operation")
    func singleTab() {
        #expect(TabCycler.wrappedNext(0, count: 1) == 0)
        #expect(TabCycler.wrappedPrevious(0, count: 1) == 0)
        #expect(TabCycler.clampedNext(0, count: 1) == 0)
        #expect(TabCycler.clampedPrevious(0, count: 1) == 0)
    }
}

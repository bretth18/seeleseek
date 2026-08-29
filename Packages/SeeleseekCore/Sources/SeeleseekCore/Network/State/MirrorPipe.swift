import Foundation

/// Builds the pipe that feeds a `@MainActor` mirror object from an actor.
///
/// The returned continuation is the actor's write side: yield a full-state
/// snapshot after every mutation. A MainActor task applies each snapshot to
/// `state` in order. The consumer is registered here, synchronously, so it
/// exists before the actor can publish anything. Buffering is
/// `.bufferingNewest(1)`: because every snapshot carries the complete
/// state, collapsing a backlog to its newest entry loses nothing, and the
/// pipe stays bounded if the main thread stalls.
///
/// Call from a `@MainActor` init, before the actor leaks to any producer.
@MainActor
func makeMirrorPipe<State: AnyObject, Snapshot: Sendable>(
    into state: State,
    apply: @escaping @MainActor (State, Snapshot) -> Void
) -> AsyncStream<Snapshot>.Continuation {
    let (updates, continuation) = AsyncStream.makeStream(
        of: Snapshot.self,
        bufferingPolicy: .bufferingNewest(1)
    )
    Task { @MainActor in
        for await snapshot in updates {
            apply(state, snapshot)
        }
    }
    return continuation
}

import Foundation
import Synchronization

/// Multi-subscriber fan-out for one event domain. Mutex-backed so both
/// sides are synchronous: `subscribe()` registers its continuation before
/// returning, so events published any time after `subscribe()` returns are
/// delivered (AsyncStream buffers until the consumer task starts
/// iterating; events published BEFORE subscription are dropped by design —
/// subscribe before `connect()`). `publish(_:)` is a plain synchronous
/// yield from the producer, so emission order is delivery order for every
/// subscriber.
public final class EventChannel<Event: Sendable>: Sendable {
    private let subscribers = Mutex<[UUID: AsyncStream<Event>.Continuation]>([:])

    /// Each call returns a fresh stream; cancelling the consuming Task
    /// tears down the continuation.
    ///
    /// `bufferingPolicy` is the subscriber's back-pressure contract: it
    /// bounds how many undelivered events queue while the consumer is
    /// busy. The default `.unbounded` never drops — required where a lost
    /// event breaks something (a transfer event that never arrives hangs
    /// its transfer). Hot domains whose consumers can fall behind under a
    /// flood (search results, social status storms) should pass
    /// `.bufferingOldest(n)`: overflow is
    /// tail-dropped like a network queue, so events already accepted are
    /// never displaced and the consumer drains in arrival order. A
    /// dropped event is gone for every purpose — pick `n` far above any
    /// realistic backlog so the bound only bites pathological floods.
    public func subscribe(
        bufferingPolicy: AsyncStream<Event>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Event> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let id = UUID()
            subscribers.withLock { $0[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.subscribers.withLock { _ = $0.removeValue(forKey: id) }
            }
        }
    }

    public func publish(_ event: Event) {
        let active = subscribers.withLock { Array($0.values) }
        for continuation in active {
            continuation.yield(event)
        }
    }

    var _subscriberCountForTest: Int {
        subscribers.withLock { $0.count }
    }
}

/// The `NetworkClient` event surface: one channel per domain. See
/// `NetworkEvents.swift` for the domain split and the ordering contract.
public final class NetworkEventBus: Sendable {
    public let chat = EventChannel<ChatEvent>()
    public let social = EventChannel<SocialEvent>()
    public let search = EventChannel<SearchEvent>()
    public let connection = EventChannel<ConnectionEvent>()
    public let transfers = EventChannel<TransferEvent>()
    public let transferNotices = EventChannel<TransferNoticeEvent>()

    public init() {}
}

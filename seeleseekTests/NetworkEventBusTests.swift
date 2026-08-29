import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// Pins the contracts the event-bus refactor depends on: synchronous
/// subscription (no lost events after `subscribe()` returns), per-
/// subscriber FIFO delivery, multi-subscriber fan-out, and teardown on
/// consumer cancellation. See `NetworkEventBus.swift`.
@MainActor
@Suite("Network event bus")
struct NetworkEventBusTests {

    @Test("Events published after subscribe() are delivered in order to every subscriber")
    func fanOutPreservesOrder() async {
        let channel = EventChannel<Int>()
        let streamA = channel.subscribe()
        let streamB = channel.subscribe()

        // Publish before either consumer task starts iterating — the
        // stream buffers from registration, not from first iteration.
        channel.publish(1)
        channel.publish(2)
        channel.publish(3)

        func collectThree(_ stream: AsyncStream<Int>) async -> [Int] {
            var seen: [Int] = []
            for await value in stream {
                seen.append(value)
                if seen.count == 3 { break }
            }
            return seen
        }
        let a = await collectThree(streamA)
        let b = await collectThree(streamB)
        #expect(a == [1, 2, 3])
        #expect(b == [1, 2, 3])
    }

    @Test("Events published before subscribe() are dropped by design")
    func preSubscriptionEventsAreDropped() async {
        let channel = EventChannel<Int>()
        channel.publish(99)

        let stream = channel.subscribe()
        channel.publish(1)

        var first: Int?
        for await value in stream {
            first = value
            break
        }
        // 99 was published pre-subscription — this is why app wiring must
        // complete before connect() can produce events.
        #expect(first == 1)
    }

    @Test("Cancelling the consumer tears down its continuation")
    func cancellationRemovesSubscriber() async throws {
        let channel = EventChannel<Int>()
        #expect(channel._subscriberCountForTest == 0)

        let stream = channel.subscribe()
        #expect(channel._subscriberCountForTest == 1)

        let consumer = Task {
            for await _ in stream {}
        }
        consumer.cancel()
        _ = await consumer.value

        // Termination is delivered on cancellation; poll briefly for the
        // onTermination cleanup to land.
        for _ in 0..<50 where channel._subscriberCountForTest != 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(channel._subscriberCountForTest == 0)
    }

    @Test("NetworkClient wiring: emitted search events reach a bus subscriber")
    func clientEmissionReachesSubscriber() async {
        let client = NetworkClient()
        let stream = client.events.search.subscribe()

        await client.emit(.results(token: 7, results: [SearchResult(username: "u", filename: "f\\a.flac", size: 1)]))

        var received: (token: UInt32, count: Int)?
        for await event in stream {
            if case .results(let token, let results) = event {
                received = (token, results.count)
            }
            break
        }
        #expect(received?.token == 7)
        #expect(received?.count == 1)
    }

    @Test("Connection events reach a bus subscriber in order")
    func connectionEventsDeliverInOrder() async {
        let client = NetworkClient()
        let stream = client.events.connection.subscribe()

        await client.emit(.statusChanged(.connecting))
        await client.emit(.statusChanged(.disconnected))

        var seen: [ConnectionStatus] = []
        for await event in stream {
            if case .statusChanged(let status) = event {
                seen.append(status)
            }
            if seen.count == 2 { break }
        }
        #expect(seen == [.connecting, .disconnected])
    }

    @Test("Wishlist token space is disjoint from search tokens")
    func wishlistTokenSpace() {
        // AppState's search-domain consumer routes on isWishlistToken —
        // the high bit partitions the spaces, so a regular search token
        // can never be routed to the wishlist and vice versa.
        let wishlist = WishlistState()
        #expect(!wishlist.isWishlistToken(0))
        #expect(!wishlist.isWishlistToken(7))
        #expect(!wishlist.isWishlistToken(0x7FFF_FFFF))
        #expect(wishlist.isWishlistToken(0x8000_0000))
        #expect(wishlist.isWishlistToken(0xFFFF_FFFF))
    }
}

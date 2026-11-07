import Testing
import Foundation
import Synchronization
@testable import SeeleseekCore
@testable import seeleseek

/// `PeerConnection.send` resumes only once the kernel takes the bytes, so a
/// peer that stops reading holds every send queued behind it. Fan-outs to
/// several peers must not let that peer delay the others.
@MainActor
@Suite("Per-peer fan-out isolation", .serialized, .timeLimit(.minutes(1)))
struct PeerFanOutTests {

    @Test("A backpressured distributed child does not keep a search from the other children")
    func distributedSearchReachesHealthyChild() async throws {
        let stalled = try await LoopbackPeer.make(username: "slow", reading: false)
        let healthy = try await LoopbackPeer.make(username: "fast", reading: true)
        let client = NetworkClient()
        // Stalled child first: a serial loop would never reach the healthy one.
        await client.addDistributedChild(stalled.connection)
        await client.addDistributedChild(healthy.connection)
        await stalled.stall()

        let finished = Flag()
        let forward = Task {
            await client.forwardDistributedSearch(unknown: 1, username: "alice", token: 7, query: "needle")
            finished.set()
        }

        var payload = Data()
        payload.appendUInt8(DistributedMessageCode.searchRequest.rawValue)
        payload.appendUInt32(1)
        payload.appendString("alice")
        payload.appendUInt32(7)
        payload.appendString("needle")
        var expected = Data()
        expected.appendUInt32(UInt32(payload.count))
        expected.append(payload)

        #expect(await healthy.waitToReceive(expected))
        #expect(!finished.isSet, "premise: the stalled child's send is still pending")

        await stalled.close()
        await healthy.close()
        await forward.value
    }

    @Test("Queue positions reach other peers, in order, while one queued peer is backpressured")
    func uploadQueuePositionsReachHealthyPeer() async throws {
        let manager = UploadManager()
        let tracking = MockTransferTracking()
        let client = NetworkClient()
        await manager._setTransferStateForTest(tracking)
        await manager._setNetworkClientForTest(client)
        await manager._setMaxConcurrentUploadsForTest(0)

        // Enqueued before any connection is registered, so these calls send nothing.
        for (username, filename) in [("slow", "@@m\\a.mp3"), ("fast", "@@m\\b.mp3"), ("fast", "@@m\\c.mp3")] {
            let file = ShareManager.IndexedFile(localPath: "/tmp/x.mp3", sharedPath: filename, size: 1, folderID: UUID())
            #expect(await manager._enqueuePeerRequestForTest(username: username, filename: filename, file: file))
        }

        let stalled = try await LoopbackPeer.make(username: "slow", reading: false)
        let healthy = try await LoopbackPeer.make(username: "fast", reading: true)
        for (id, peer) in [("slow-1", stalled), ("fast-1", healthy)] {
            let username = id.hasPrefix("slow") ? "slow" : "fast"
            await client.peerConnectionPool._seedActiveConnectionForTest(
                .init(id: id, username: username, ip: "127.0.0.1", port: 1, state: .connected, connectionType: .peer),
                connection: peer.connection
            )
        }
        await stalled.stall()

        let finished = Flag()
        let broadcast = Task {
            await manager._processQueueForTest()
            finished.set()
        }

        let expected = MessageBuilder.placeInQueueResponseMessage(filename: "@@m\\b.mp3", place: 2)
            + MessageBuilder.placeInQueueResponseMessage(filename: "@@m\\c.mp3", place: 3)
        #expect(await healthy.waitToReceive(expected))
        #expect(!finished.isSet, "premise: the stalled peer's send is still pending")

        await stalled.close()
        await healthy.close()
        await broadcast.value
    }
}

private nonisolated final class Flag: Sendable {
    private let value = Atomic(false)
    func set() { value.store(true, ordering: .sequentiallyConsistent) }
    var isSet: Bool { value.load(ordering: .sequentiallyConsistent) }
}

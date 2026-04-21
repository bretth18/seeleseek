import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

/// End-to-end integration tests for the UserInfoReply fan-out:
/// MessageParser.parseUserInfoReply → SocialState.applyUserInfo → viewingProfile.
///
/// These tests exercise the exact code paths that surface a peer's description,
/// profile picture, and upload stats in the profile sheet. They exist because
/// this flow has had two bugs in quick succession (picture bytes silently
/// dropped in the parser; cache hits never surfaced at the call site), and
/// neither had test coverage to catch it.
@MainActor
@Suite("UserInfoReply → SocialState viewingProfile")
struct UserInfoReplyFlowTests {

    // MARK: - Helpers

    /// Builds a valid UserInfoReply wire payload and parses it back through the
    /// production parser. Keeps the test honest — we're not stubbing the parser.
    private func makeReply(
        description: String = "Hello there",
        picture: Data? = Data([0xFF, 0xD8, 0xFF, 0xE0]),
        totalUploads: UInt32 = 5,
        queueSize: UInt32 = 3,
        hasFreeSlots: Bool = true
    ) -> MessageParser.UserInfoReplyInfo {
        var payload = Data()
        payload.appendString(description)
        if let picture {
            payload.appendBool(true)
            payload.appendUInt32(UInt32(picture.count))
            payload.append(picture)
        } else {
            payload.appendBool(false)
        }
        payload.appendUInt32(totalUploads)
        payload.appendUInt32(queueSize)
        payload.appendBool(hasFreeSlots)

        guard let info = MessageParser.parseUserInfoReply(payload) else {
            Issue.record("Test setup: parseUserInfoReply returned nil")
            return MessageParser.UserInfoReplyInfo(
                description: "", hasPicture: false, pictureData: nil,
                totalUploads: 0, queueSize: 0, hasFreeSlots: false
            )
        }
        return info
    }

    private func makeState(viewing username: String?) -> SocialState {
        let state = SocialState()
        if let username {
            state.viewingProfile = UserProfile(username: username)
        }
        return state
    }

    // MARK: - Fresh-fetch path

    @Test("applyUserInfo populates the currently-viewed profile")
    func testApplyPopulatesMatchingProfile() {
        let state = makeState(viewing: "mfs:321")
        let info = makeReply(description: "Long-time Soulseek user", picture: Data([0x01, 0x02, 0x03]))

        state.applyUserInfo(info, for: "mfs:321")

        #expect(state.viewingProfile?.description == "Long-time Soulseek user")
        #expect(state.viewingProfile?.picture == Data([0x01, 0x02, 0x03]))
        #expect(state.viewingProfile?.totalUploads == 5)
        #expect(state.viewingProfile?.queueSize == 3)
        #expect(state.viewingProfile?.hasFreeSlots == true)
    }

    // MARK: - Cache-hit path (the regression that prompted these tests)

    @Test("Second open of same profile re-populates from applyUserInfo")
    func testCacheHitRepopulatesOnReopen() {
        let state = makeState(viewing: "repeatuser")
        let info = makeReply(description: "First time", picture: Data([0xAA]))

        // First open: fresh reply arrives, handler path fires applyUserInfo.
        state.applyUserInfo(info, for: "repeatuser")
        #expect(state.viewingProfile?.description == "First time")

        // Simulate the user closing the sheet and reopening the same profile.
        // loadProfile reseeds viewingProfile to a basic UserProfile with no
        // description/picture, then the cached fetchUserInfo result comes
        // back and MUST be applied — that's the behaviour the earlier
        // regression was missing.
        state.viewingProfile = UserProfile(username: "repeatuser")
        #expect(state.viewingProfile?.description == "")
        #expect(state.viewingProfile?.picture == nil)

        state.applyUserInfo(info, for: "repeatuser")
        #expect(state.viewingProfile?.description == "First time")
        #expect(state.viewingProfile?.picture == Data([0xAA]))
    }

    // MARK: - Ordering / no-op guards

    @Test("applyUserInfo with no viewingProfile is a no-op")
    func testApplyNoOpWhenNothingIsViewing() {
        let state = makeState(viewing: nil)
        let info = makeReply(description: "Should not appear anywhere")

        state.applyUserInfo(info, for: "somebody")

        #expect(state.viewingProfile == nil)
    }

    @Test("applyUserInfo for a different user does not clobber current viewing")
    func testApplyDoesNotClobberDifferentUser() {
        let state = makeState(viewing: "alice")
        state.viewingProfile?.description = "alice's original bio"
        let info = makeReply(description: "bob's bio")

        // Reply arrives late for bob, but we're already viewing alice.
        state.applyUserInfo(info, for: "bob")

        #expect(state.viewingProfile?.username == "alice")
        #expect(state.viewingProfile?.description == "alice's original bio")
    }

    // MARK: - Empty payload surfaces correctly

    @Test("Peer with no picture surfaces nil, not garbage")
    func testEmptyPictureSurfacesNil() {
        let state = makeState(viewing: "nopfp")
        let info = makeReply(picture: nil)

        state.applyUserInfo(info, for: "nopfp")

        #expect(state.viewingProfile?.picture == nil)
        #expect(state.viewingProfile?.description == "Hello there")
    }

    // MARK: - Parser round-trip integrity (the fix for the original picture bug)

    @Test("Large pictures survive parse-then-apply intact")
    func testLargePictureRoundTrip() {
        let bigPicture = Data((0..<40_000).map { UInt8($0 & 0xFF) })
        let info = makeReply(picture: bigPicture)
        let state = makeState(viewing: "bigpic")

        state.applyUserInfo(info, for: "bigpic")

        #expect(state.viewingProfile?.picture == bigPicture)
        #expect(state.viewingProfile?.picture?.count == 40_000)
    }
}

// MARK: - TransferReply reason → TransferStatus mapping

@Suite("UploadManager reject-reason mapping")
struct UploadManagerRejectStatusTests {

    @Test("Queued rejection is not a failure")
    func testQueued() {
        #expect(UploadManager.status(forReject: "Queued") == .queued)
        #expect(UploadManager.status(forReject: "queued") == .queued)
        // Tolerate trailing punctuation / whitespace variants.
        #expect(UploadManager.status(forReject: "Queued.") == .queued)
        #expect(UploadManager.status(forReject: " Queued ") == .queued)
    }

    @Test("Cancelled rejection maps to cancelled")
    func testCancelled() {
        #expect(UploadManager.status(forReject: "Cancelled") == .cancelled)
        #expect(UploadManager.status(forReject: "Canceled") == .cancelled)
    }

    @Test("Unknown reason maps to failed")
    func testFailedByDefault() {
        #expect(UploadManager.status(forReject: nil) == .failed)
        #expect(UploadManager.status(forReject: "") == .failed)
        #expect(UploadManager.status(forReject: "File not shared") == .failed)
        #expect(UploadManager.status(forReject: "User is offline") == .failed)
    }
}

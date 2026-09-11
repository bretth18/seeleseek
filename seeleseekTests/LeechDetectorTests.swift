import Foundation
import Testing
@testable import seeleseek
@testable import SeeleseekCore

@Suite("LeechDetector")
@MainActor
struct LeechDetectorTests {

    @MainActor
    private final class Harness {
        var statsRequests: [String] = []
        var browseRequests: [String] = []
        var messages: [(username: String, text: String)] = []
        var blocked: [String] = []
        var logs: [String] = []
        var buddies: Set<String> = []
        var browseResult: Result<LeechDetector.ShareCounts, Error> = .failure(CancellationError())
        var savedSettings: LeechSettings?
        var names: [String: [String]] = [:]

        let detector: LeechDetector

        init(action: LeechAction, minFiles: UInt32 = 10, minFolders: UInt32 = 1) {
            detector = LeechDetector()
            detector.settings.enabled = true
            detector.settings.action = action
            detector.settings.minSharedFiles = minFiles
            detector.settings.minSharedFolders = minFolders
            detector.verdictTimeout = .seconds(2)
            detector.services = LeechDetector.Services(
                requestStats: { [weak self] user in self?.statsRequests.append(user) },
                browseShareCounts: { [weak self] user in
                    guard let self else { throw CancellationError() }
                    self.browseRequests.append(user)
                    return try self.browseResult.get()
                },
                sendPrivateMessage: { [weak self] user, text in self?.messages.append((user, text)) },
                isBuddy: { [weak self] user in self?.buddies.contains(user) ?? false },
                blockUser: { [weak self] user in self?.blocked.append(user) },
                log: { [weak self] title, _, _ in self?.logs.append(title) },
                loadSettings: { [weak self] in self?.savedSettings },
                saveSettings: { [weak self] settings in self?.savedSettings = settings },
                loadNames: { [weak self] key in self?.names[key] },
                saveNames: { [weak self] key, value in self?.names[key] = value }
            )
        }

        func request(_ user: String, stage: UploadPolicyStage = .request) async -> UploadPolicyDecision {
            await detector.evaluate(UploadPolicyRequest(username: user, filename: "@@x\\a.mp3", stage: stage))
        }

        /// Lets the detector's fire-and-forget Tasks (stats request,
        /// browse, persistence) run.
        func settle() async {
            for _ in 0..<20 { await Task.yield() }
        }
    }

    @Test("Disabled detector allows without probing")
    func disabledAllows() async {
        let h = Harness(action: .deny)
        h.detector.settings.enabled = false
        #expect(await h.request("bob") == .allow)
        #expect(h.statsRequests.isEmpty)
    }

    @Test("One probe per user")
    func probeOncePerUser() async {
        let h = Harness(action: .warn)
        #expect(await h.request("bob") == .allow)
        #expect(await h.request("bob") == .allow)
        #expect(await h.request("bob", stage: .start) == .allow)
        await h.settle()
        #expect(h.statsRequests == ["bob"])

        h.detector.receivedStats(username: "bob", files: 500, folders: 20)
        #expect(h.detector.probes["bob"] == .okay)
        #expect(!h.detector.isLeecher("bob"))
        #expect(h.logs.isEmpty)
    }

    @Test("Unsolicited stats are ignored")
    func unsolicitedStatsIgnored() {
        let h = Harness(action: .warn)
        h.detector.receivedStats(username: "stranger", files: 0, folders: 0)
        #expect(h.detector.probes["stranger"] == nil)
        #expect(h.browseRequests.isEmpty)
    }

    @Test("Buddies are never probed")
    func buddiesExempt() async {
        let h = Harness(action: .deny)
        h.buddies = ["pal"]
        #expect(await h.request("pal") == .allow)
        await h.settle()
        #expect(h.statsRequests.isEmpty)
        #expect(h.detector.probes["pal"] == .okay)
    }

    @Test("Warn flags, logs, persists, never denies")
    func warnFlagsAndLogs() async throws {
        let h = Harness(action: .warn)
        _ = await h.request("bob")
        h.detector.receivedStats(username: "bob", files: 3, folders: 1)
        await h.settle()

        #expect(h.detector.isLeecher("bob"))
        #expect(h.detector.shareCounts["bob"] == .init(files: 3, folders: 1))
        #expect(h.logs == ["Leech detected: bob"])
        #expect(await h.request("bob", stage: .start) == .allow)
        #expect(h.messages.isEmpty)
        #expect(h.blocked.isEmpty)
        #expect(h.names["leechDetected"] == ["bob"])
    }

    @Test("Disabling detection hides flags without forgetting them")
    func disableHidesFlags() async {
        let h = Harness(action: .warn)
        _ = await h.request("bob")
        h.detector.receivedStats(username: "bob", files: 0, folders: 1)
        h.detector.settings.enabled = false
        #expect(!h.detector.isLeecher("bob"))
        #expect(h.detector.detectedLeechers == ["bob"])
    }

    @Test("Flagged user who starts sharing is unflagged on the next probe")
    func unflagWhenSharing() async {
        let h = Harness(action: .warn)
        _ = await h.request("bob")
        h.detector.receivedStats(username: "bob", files: 0, folders: 1)
        await h.settle()

        let h2 = Harness(action: .warn)
        h2.names = h.names
        await h2.detector.load()
        #expect(h2.detector.isLeecher("bob"))
        _ = await h2.request("bob")
        h2.detector.receivedStats(username: "bob", files: 200, folders: 10)
        await h2.settle()
        #expect(!h2.detector.isLeecher("bob"))
        #expect(h2.names["leechDetected"] == [])
    }

    @Test("Server zero verified by browse")
    func zeroVerifiedByBrowse() async {
        let h = Harness(action: .warn)
        h.browseResult = .success(.init(files: 40, folders: 4))
        _ = await h.request("bob")
        h.detector.receivedStats(username: "bob", files: 0, folders: 0)
        #expect(h.detector.probes["bob"] == .verifyingShares)
        await h.settle()
        #expect(h.browseRequests == ["bob"])
        #expect(h.detector.probes["bob"] == .okay)
    }

    @Test("Browse failure lets the server's zero stand")
    func browseFailureFlags() async {
        let h = Harness(action: .warn)
        _ = await h.request("bob")
        h.detector.receivedStats(username: "bob", files: 0, folders: 0)
        await h.settle()
        #expect(h.detector.isLeecher("bob"))
        #expect(h.detector.shareCounts["bob"] == .init(files: 0, folders: 0))
    }

    @Test("Deny holds the first request until the verdict")
    func denyWaitsForVerdict() async {
        let h = Harness(action: .deny)
        let pending = Task { await h.request("bob") }
        await h.settle()
        #expect(h.statsRequests == ["bob"])
        h.detector.receivedStats(username: "bob", files: 1, folders: 1)
        #expect(await pending.value == .deny(reason: "File not shared."))
        #expect(await h.request("bob", stage: .start) == .deny(reason: "File not shared."))
    }

    @Test("Deny allows a sharer")
    func denyAllowsSharer() async {
        let h = Harness(action: .deny)
        let pending = Task { await h.request("bob") }
        await h.settle()
        h.detector.receivedStats(username: "bob", files: 100, folders: 5)
        #expect(await pending.value == .allow)
    }

    @Test("Deny fails open on timeout, verdict applies at start")
    func denyTimesOutOpen() async {
        let h = Harness(action: .deny)
        h.detector.verdictTimeout = .milliseconds(30)
        let started = ContinuousClock.now
        #expect(await h.request("bob") == .allow)
        #expect(ContinuousClock.now - started < .seconds(1))
        h.detector.receivedStats(username: "bob", files: 0, folders: 1)
        #expect(await h.request("bob", stage: .start) == .deny(reason: "File not shared."))
    }

    @Test("Concurrent requests share one probe")
    func concurrentRequestsShareProbe() async {
        let h = Harness(action: .deny)
        let tasks = (0..<5).map { _ in Task { await h.request("bob") } }
        await h.settle()
        #expect(h.statsRequests == ["bob"])
        h.detector.receivedStats(username: "bob", files: 0, folders: 5)
        for task in tasks {
            #expect(await task.value == .deny(reason: "File not shared."))
        }
    }

    @Test("Persisted leecher is denied without waiting")
    func persistedLeecherDeniedImmediately() async {
        let h = Harness(action: .deny)
        h.names["leechDetected"] = ["bob"]
        await h.detector.load()
        h.detector.verdictTimeout = .seconds(10)
        let started = ContinuousClock.now
        #expect(await h.request("bob") == .deny(reason: "File not shared."))
        #expect(ContinuousClock.now - started < .seconds(1))
    }

    @Test("Message sent once after first completed upload")
    func messageAfterUploadOnce() async {
        let h = Harness(action: .message, minFiles: 25, minFolders: 2)
        h.detector.settings.customMessage = "Share %files% files in %folders% folders.\n\nThanks!"
        #expect(await h.request("bob") == .allow)
        h.detector.receivedStats(username: "bob", files: 1, folders: 1)
        #expect(h.messages.isEmpty)

        await h.detector.uploadDidComplete(username: "bob")
        await h.detector.uploadDidComplete(username: "bob")
        await h.settle()

        #expect(h.messages.map(\.text) == ["Share 25 files in 2 folders.", "Thanks!"])
        #expect(h.messages.allSatisfy { $0.username == "bob" })
        #expect(h.names["leechMessaged"] == ["bob"])
    }

    @Test("Messaged users are not messaged in a later session")
    func messageNotRepeatedAcrossSessions() async {
        let h = Harness(action: .message)
        h.names["leechMessaged"] = ["bob"]
        await h.detector.load()
        _ = await h.request("bob")
        h.detector.receivedStats(username: "bob", files: 0, folders: 1)
        await h.detector.uploadDidComplete(username: "bob")
        #expect(h.messages.isEmpty)
    }

    @Test("No message outside the message action")
    func noMessageOutsideMessageAction() async {
        let h = Harness(action: .warn)
        _ = await h.request("bob")
        h.detector.receivedStats(username: "bob", files: 0, folders: 1)
        await h.detector.uploadDidComplete(username: "bob")
        #expect(h.messages.isEmpty)
    }

    @Test("Block denies the triggering request and blocks")
    func blockAction() async {
        let h = Harness(action: .block)
        let pending = Task { await h.request("bob") }
        await h.settle()
        h.detector.receivedStats(username: "bob", files: 2, folders: 1)
        #expect(await pending.value == .deny(reason: "File not shared."))
        await h.settle()
        #expect(h.blocked == ["bob"])
    }

    @Test("Forget, manual block, and Clear persist")
    func forgetBlockClear() async {
        let h = Harness(action: .warn)
        for user in ["a", "b", "c"] {
            _ = await h.request(user)
            h.detector.receivedStats(username: user, files: 0, folders: 1)
        }
        #expect(h.detector.detectedLeechers == ["a", "b", "c"])

        h.detector.forget("a")
        #expect(h.detector.detectedLeechers == ["b", "c"])
        #expect(h.detector.probes["a"] == nil)

        await h.detector.block("b")
        #expect(h.blocked == ["b"])
        #expect(h.detector.detectedLeechers == ["c"])

        h.detector.clearDetected()
        await h.settle()
        #expect(h.detector.detectedLeechers.isEmpty)
        #expect(h.names["leechDetected"] == [])
        #expect(h.names["leechMessaged"] == [])
    }

    @Test("Settings edits save; load does not echo a save")
    func settingsAutosave() async {
        let h = Harness(action: .warn)
        h.savedSettings = nil
        h.detector.settings.minSharedFiles = 42
        await h.settle()
        #expect(h.savedSettings?.minSharedFiles == 42)

        h.savedSettings = LeechSettings(minSharedFiles: 7)
        await h.detector.load()
        #expect(h.detector.settings.minSharedFiles == 7)
        await h.settle()
        #expect(h.savedSettings?.minSharedFiles == 7)
    }

    @Test("Legacy settings JSON with removed keys still decodes")
    func legacySettingsDecode() throws {
        let json = #"{"enabled":true,"minSharedFiles":7,"minSharedFolders":2,"action":"deny","customMessage":"hi","blockAfterWarning":true}"#
        let settings = try JSONDecoder().decode(LeechSettings.self, from: Data(json.utf8))
        #expect(settings.minSharedFiles == 7)
        #expect(settings.action == .deny)
    }
}

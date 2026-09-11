import Foundation
import Testing
@testable import SeeleseekCore

@Suite("UploadManager policy chain")
struct UploadPolicyChainTests {

    private actor Recorder {
        var evaluated: [String] = []
        var completed: [String] = []
        func recordEvaluation(_ name: String) { evaluated.append(name) }
        func recordCompletion(_ username: String) { completed.append(username) }
    }

    private struct StubPolicy: UploadPolicy {
        let name: String
        let decision: UploadPolicyDecision
        let recorder: Recorder

        func evaluate(_ request: UploadPolicyRequest) async -> UploadPolicyDecision {
            await recorder.recordEvaluation(name)
            return decision
        }

        func uploadDidComplete(username: String) async {
            await recorder.recordCompletion(username)
        }
    }

    @Test("First deny wins and later policies are not consulted")
    func firstDenyWins() async {
        let recorder = Recorder()
        let manager = UploadManager()
        await manager.setUploadPolicies([
            StubPolicy(name: "a", decision: .allow, recorder: recorder),
            StubPolicy(name: "b", decision: .deny(reason: "Banned"), recorder: recorder),
            StubPolicy(name: "c", decision: .deny(reason: "Too many files"), recorder: recorder),
        ])

        let decision = await manager._evaluateUploadPoliciesForTest(username: "u", filename: "f", stage: .start)

        #expect(decision == .deny(reason: "Banned"))
        #expect(await recorder.evaluated == ["a", "b"])
    }

    @Test("Completion reaches every policy")
    func completionFanOut() async throws {
        let recorder = Recorder()
        let manager = UploadManager()
        await manager.setUploadPolicies([
            StubPolicy(name: "a", decision: .allow, recorder: recorder),
            StubPolicy(name: "b", decision: .deny(reason: "x"), recorder: recorder),
        ])

        await manager._notifyUploadCompletedForTest(username: "peer")

        for _ in 0..<200 where await recorder.completed.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await recorder.completed == ["peer", "peer"])
    }
}

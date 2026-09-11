import Foundation

public enum UploadPolicyStage: Sendable {
    /// A peer's first QueueUpload / TransferRequest for the file.
    case request
    /// A queued item is about to be driven because a slot is free.
    case start
    /// An automatic retry is about to re-drive a failed row.
    case retry
}

public struct UploadPolicyRequest: Sendable {
    public let username: String
    public let filename: String
    public let stage: UploadPolicyStage

    public init(username: String, filename: String, stage: UploadPolicyStage) {
        self.username = username
        self.filename = filename
        self.stage = stage
    }
}

public enum UploadPolicyDecision: Sendable, Equatable {
    case allow
    /// `reason` is what the peer sees (UploadDenied / TransferReply).
    case deny(reason: String)
}

public enum UploadDenialReason {
    /// Also used for unknown files, so a refused peer cannot tell a
    /// policy refusal from a missing share.
    public static let notShared = "File not shared."
}

/// Run in registration order; the first `.deny` wins.
public protocol UploadPolicy: Sendable {
    func evaluate(_ request: UploadPolicyRequest) async -> UploadPolicyDecision
    func uploadDidComplete(username: String) async
}

public extension UploadPolicy {
    func uploadDidComplete(username: String) async {}
}

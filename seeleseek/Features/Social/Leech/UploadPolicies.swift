import Foundation
import SeeleseekCore

struct PatternBlockPolicy: UploadPolicy {
    let settings: SettingsState

    @MainActor
    func evaluate(_ request: UploadPolicyRequest) async -> UploadPolicyDecision {
        let patterns = settings.activeBlockedPatterns
        guard !patterns.isEmpty,
              UsernamePatternMatcher.matches(request.username, anyOfCompiled: patterns) else {
            return .allow
        }
        return .deny(reason: UploadDenialReason.notShared)
    }
}

struct BlocklistPolicy: UploadPolicy {
    let socialState: SocialState

    @MainActor
    func evaluate(_ request: UploadPolicyRequest) async -> UploadPolicyDecision {
        socialState.isBlocked(request.username) ? .deny(reason: UploadDenialReason.notShared) : .allow
    }
}

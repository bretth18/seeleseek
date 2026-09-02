import Foundation

/// Policy for responding to other users' distributed searches. Pushed
/// down from app settings via `NetworkClient.updateSearchResponsePolicy`;
/// the per-query hot path (5-50 queries/sec on a busy relay) reads it
/// locally.
public struct SearchResponsePolicy: Sendable, Equatable {
    public var enabled: Bool
    public var minQueryLength: Int
    public var maxResults: Int

    public init(enabled: Bool = true, minQueryLength: Int = 3, maxResults: Int = 50) {
        self.enabled = enabled
        self.minQueryLength = minQueryLength
        self.maxResults = maxResults
    }
}

/// Our own profile served to peers in UserInfoResponse. Pushed down from
/// the app via `NetworkClient.updateProfileData` whenever the user edits
/// their profile.
public struct ProfileData: Sendable, Equatable {
    public var description: String
    public var picture: Data?

    public init(description: String = "", picture: Data? = nil) {
        self.description = description
        self.picture = picture
    }

    /// Description with the client-default fallback applied — peers always
    /// see something, even before the user writes a profile.
    public var resolvedDescription: String {
        description.isEmpty ? "SeeleSeek - Soulseek client for macOS" : description
    }
}

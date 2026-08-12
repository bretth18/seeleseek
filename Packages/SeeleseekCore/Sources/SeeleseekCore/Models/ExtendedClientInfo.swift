import Foundation

/// A peer's advertised protocol extensions, from ExtendedClientInfo (code 10000).
///
/// Presence means "this peer speaks extensions", not "this peer is SeeleSeek" —
/// any client may implement the handshake. Never infer identity from it.
public struct ExtendedClientInfo: Sendable, Equatable {
    /// Revision of the ExtendedClientInfo format itself, not of any individual
    /// capability. Owned here rather than on the builder or the parser, since
    /// both sides validate against it.
    public static let currentRevision: UInt32 = 1

    /// What we advertise about ourselves. The spec makes this optional, but a
    /// field every implementer leaves empty is a dead field, and knowing what
    /// is actually deployed is the point of publishing the handshake. It adds
    /// nothing to our fingerprint that the capability list does not already
    /// give away. Version comes from the host bundle so it cannot go stale.
    public static let localClientInfo: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "SeeleSeek/\(version) (https://seeleseek.net)"
    }()

    public let revision: UInt32
    /// Free-form and optional; peers may send an empty string. Display only —
    /// it is self-reported and trivially spoofed, so never branch on it.
    public let clientInfo: String

    /// Wire name → the code this peer binds it to.
    public let capabilities: [String: UInt32]

    public init(revision: UInt32, clientInfo: String, capabilities: [String: UInt32]) {
        self.revision = revision
        self.clientInfo = clientInfo
        self.capabilities = capabilities
    }

    /// Exact (name, code) match, per the spec's rule that a mismatched code
    /// means we must not send that message.
    public func supports(_ code: ExtendedClientInfoCode) -> Bool {
        capabilities[code.wireName] == code.rawValue
    }
}

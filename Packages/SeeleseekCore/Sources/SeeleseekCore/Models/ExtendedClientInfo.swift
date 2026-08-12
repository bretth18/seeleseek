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

    public let revision: UInt32
    /// Free-form and optional; peers may send an empty string. Display only.
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

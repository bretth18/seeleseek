import Foundation

/// A peer's advertised protocol extensions, from ExtendedClientInfo (code 10000).
///
/// Presence means "this peer speaks extensions", not "this peer is SeeleSeek" —
/// any client may implement the handshake. Never infer identity from it.
public struct ExtendedClientInfo: Sendable, Equatable {
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
    public func supports(_ code: SeeleSeekExtendedClientInfoCode) -> Bool {
        capabilities[code.wireName] == code.rawValue
    }

    /// Synthesised for SeeleSeek 1.x peers, which predate this handshake and
    /// send a bare uint8 version at code 10000. They support the same three
    /// codes implicitly. Remove once 1.x is no longer in the wild.
    public static func legacySeeleSeek(version: UInt8) -> ExtendedClientInfo {
        ExtendedClientInfo(
            revision: 0,
            clientInfo: "SeeleSeek/\(version).x",
            capabilities: Dictionary(
                uniqueKeysWithValues: SeeleSeekExtendedClientInfoCode.allCases.map {
                    ($0.wireName, $0.rawValue)
                }
            )
        )
    }
}

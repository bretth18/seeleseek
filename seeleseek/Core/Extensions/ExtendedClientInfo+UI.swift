import SwiftUI
import SeeleseekCore

extension ExtendedClientInfo {
    /// Badge text for a peer that advertised extensions.
    ///
    /// Falls back to a generic label because `clientInfo` is optional on the
    /// wire and we send it empty ourselves, so most advertising peers have no
    /// string to show. Naming a client here would also claim an identity the
    /// handshake cannot establish.
    var displayLabel: String {
        clientInfo.isEmpty ? "extended client" : clientInfo
    }
}

import Foundation
import SeeleseekCore

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notConnected

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConnected:
            "SeeleSeek is not connected to the network. Open the app and log in first."
        }
    }
}

import Foundation

public struct ExtendedClientInfo: Sendable, Equatable {
    public let revision: UInt32
    public let clientInfo: String
    
    public let capabilities: [String: UInt32]
    
    public func supports(_ code: SeeleSeekExtendedClientInfoCode) -> Bool {
        capabilities[code.wireName] == code.rawValue
    }
}

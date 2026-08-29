import Foundation

/// Complete connection state as one value, yielded by the client at every
/// state transition.
public struct NetworkStatusSnapshot: Sendable, Equatable {
    public var isConnecting = false
    public var isConnected = false
    public var connectionError: String?
    public var username = ""
    public var loggedIn = false
    public var listenPort: UInt16 = 0
    public var obfuscatedPort: UInt16 = 0
    public var externalIP: String?
    public var localIP: String?
    public var natGateway: String?
    public var natMappings: [NATService.PortMapping] = []
    public var acceptDistributedChildren = true
    public var distributedBranchLevel: UInt32 = 0
    public var distributedBranchRoot = ""
    public var distributedChildrenCount = 0

    public init() {}
}

/// What views observe for connection state. All transitions are
/// low-frequency (connect/login/NAT setup); the per-property change guards
/// in `apply` keep observation invalidations tight.
@Observable
@MainActor
public final class NetworkStatusState {
    public private(set) var isConnecting = false
    public private(set) var isConnected = false
    public private(set) var connectionError: String?
    public private(set) var username = ""
    public private(set) var loggedIn = false
    public private(set) var listenPort: UInt16 = 0
    public private(set) var obfuscatedPort: UInt16 = 0
    public private(set) var externalIP: String?
    public private(set) var localIP: String?
    public private(set) var natGateway: String?
    public private(set) var natMappings: [NATService.PortMapping] = []
    public private(set) var acceptDistributedChildren = true
    public private(set) var distributedBranchLevel: UInt32 = 0
    public private(set) var distributedBranchRoot = ""
    public private(set) var distributedChildrenCount = 0

    public init() {}

    public func apply(_ s: NetworkStatusSnapshot) {
        if isConnecting != s.isConnecting { isConnecting = s.isConnecting }
        if isConnected != s.isConnected { isConnected = s.isConnected }
        if connectionError != s.connectionError { connectionError = s.connectionError }
        if username != s.username { username = s.username }
        if loggedIn != s.loggedIn { loggedIn = s.loggedIn }
        if listenPort != s.listenPort { listenPort = s.listenPort }
        if obfuscatedPort != s.obfuscatedPort { obfuscatedPort = s.obfuscatedPort }
        if externalIP != s.externalIP { externalIP = s.externalIP }
        if localIP != s.localIP { localIP = s.localIP }
        if natGateway != s.natGateway { natGateway = s.natGateway }
        if natMappings != s.natMappings { natMappings = s.natMappings }
        if acceptDistributedChildren != s.acceptDistributedChildren { acceptDistributedChildren = s.acceptDistributedChildren }
        if distributedBranchLevel != s.distributedBranchLevel { distributedBranchLevel = s.distributedBranchLevel }
        if distributedBranchRoot != s.distributedBranchRoot { distributedBranchRoot = s.distributedBranchRoot }
        if distributedChildrenCount != s.distributedChildrenCount { distributedChildrenCount = s.distributedChildrenCount }
    }
}

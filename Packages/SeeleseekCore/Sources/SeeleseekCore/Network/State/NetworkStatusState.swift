import Foundation

/// Value snapshot of `NetworkClient`'s UI-facing connection state.
/// Built by the client at every state transition and applied to
/// `NetworkStatusState` — the one road from network coordination to
/// SwiftUI observation for this data.
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

/// Lightweight `@MainActor` mirror of the client's connection state — the
/// object views observe instead of the live socket coordinator. All
/// transitions are low-frequency (connect/login/NAT setup), so per-property
/// change guards keep observation invalidations tight.
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

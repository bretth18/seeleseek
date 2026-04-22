import Darwin
import Foundation
import Network
import os
import Synchronization
import SystemConfiguration

/// Handles NAT traversal using UPnP and NAT-PMP.
///
/// Mapping, teardown, and refresh all share the same raw wire code
/// (`mapPortUPnPRaw` / `mapPortNATPMPRaw`) so there's one place per protocol
/// where the byte layout has to be correct.
///
/// ## Lifecycle
///
/// Callers **must** `await removeAllMappings()` before releasing this actor.
/// Swift actor deinit can't be async, so router state cannot be cleaned up
/// from deinit — a dropped `NATService` leaves NAT-PMP mappings on the router
/// until their lease expires, and any UPnP permanent mappings (lease=0) stay
/// forever. `NetworkClient.teardown()` is the normal caller and does this
/// correctly via its `teardownTask`.
public actor NATService {
    private let logger = Logger(subsystem: "com.seeleseek", category: "NATService")

    // MARK: - Types

    public struct PortMapping: Sendable, Equatable {
        public let internalPort: UInt16
        public let externalPort: UInt16
        public let proto: String
    }

    private enum MappingMethod: Sendable { case upnp, natpmp }

    private struct InternalMapping: Sendable {
        let internalPort: UInt16
        let externalPort: UInt16
        let proto: String
        let method: MappingMethod
        /// Lease duration the router granted (seconds). `0` means permanent
        /// (no refresh needed).
        let leaseSeconds: UInt32
        var createdAt: Date
    }

    private struct UPnPGateway: Sendable {
        let ip: String
        let controlURL: String
        /// The WAN*Connection service type that owns `controlURL`. We need
        /// this for the SOAPAction header and the request body's xmlns.
        let serviceType: String
    }

    private struct CachedGateway: Sendable {
        let gateway: UPnPGateway
        let cachedAt: Date
        var isValid: Bool { Date().timeIntervalSince(cachedAt) < 300 }
    }

    // MARK: - State

    private var mappedPorts: [InternalMapping] = []
    private var externalIP: String?
    private var gatewayIP: String?
    private var cachedGateway: CachedGateway?
    private var refreshTask: Task<Void, Never>?

    // MARK: - Public Interface

    public var externalAddress: String? { externalIP }

    /// Gateway (router) IP. Populated after the first successful UPnP
    /// discovery or NAT-PMP mapping attempt.
    public var gatewayAddress: String? { gatewayIP }

    /// Active port mappings we successfully registered. Empty when running
    /// without UPnP/NAT-PMP or when all mapping attempts failed.
    public var activeMappings: [PortMapping] {
        mappedPorts.map {
            PortMapping(internalPort: $0.internalPort, externalPort: $0.externalPort, proto: $0.proto)
        }
    }

    /// Attempts to map a port using UPnP first, then NAT-PMP. On success
    /// the mapping is tracked with its method so teardown and refresh can
    /// route correctly.
    public func mapPort(_ internalPort: UInt16, externalPort: UInt16? = nil, protocol proto: String = "TCP") async throws -> UInt16 {
        let normalizedProto = proto.uppercased() == "TCP" ? "TCP" : "UDP"
        let targetExternal = externalPort ?? internalPort

        logger.debug("Attempting to map port \(internalPort) -> \(targetExternal) (\(normalizedProto))")

        // Try UPnP first
        do {
            let result = try await mapPortUPnPWithFallback(internalPort, externalPort: targetExternal, protocol: normalizedProto)
            recordMapping(
                internal: internalPort,
                external: result.port,
                proto: normalizedProto,
                method: .upnp,
                leaseSeconds: result.lease
            )
            logger.info("UPnP mapped port \(internalPort) -> \(result.port) (lease \(result.lease)s)")
            Task { @MainActor in ActivityLogger.shared?.logNATMapping(port: result.port, success: true) }
            return result.port
        } catch {
            logger.debug("UPnP failed: \(error.localizedDescription)")
        }

        // Fall back to NAT-PMP
        do {
            let lifetime: UInt32 = 3600
            let mapped = try await mapPortNATPMPRaw(internalPort, externalPort: targetExternal, protocol: normalizedProto, lifetime: lifetime)
            recordMapping(
                internal: internalPort,
                external: mapped,
                proto: normalizedProto,
                method: .natpmp,
                leaseSeconds: lifetime
            )
            logger.info("NAT-PMP mapped port \(internalPort) -> \(mapped) (lifetime \(lifetime)s)")
            Task { @MainActor in ActivityLogger.shared?.logNATMapping(port: mapped, success: true) }
            return mapped
        } catch {
            logger.debug("NAT-PMP failed: \(error.localizedDescription)")
        }

        // Neither method worked — surface the failure. For a P2P client, pretending
        // the port is reachable would mask the real "nobody can browse my shares" UX.
        logger.warning("NAT mapping failed for port \(internalPort)")
        Task { @MainActor in ActivityLogger.shared?.logNATMapping(port: internalPort, success: false) }
        throw NATError.mappingFailed
    }

    /// Removes all port mappings. Waits for any in-flight refresh to drain
    /// before tearing down so we don't race ourselves.
    public func removeAllMappings() async {
        refreshTask?.cancel()
        await refreshTask?.value
        refreshTask = nil

        for mapping in mappedPorts {
            switch mapping.method {
            case .upnp:
                try? await removePortMappingUPnP(mapping.externalPort, protocol: mapping.proto)
            case .natpmp:
                try? await removePortMappingNATPMP(mapping.internalPort, protocol: mapping.proto)
            }
        }
        mappedPorts.removeAll()
    }

    /// Discovers external IP via UPnP → STUN → web fallback.
    public func discoverExternalIP() async -> String? {
        if let ip = try? await getExternalIPUPnP() {
            externalIP = ip
            return ip
        }
        if let ip = try? await getExternalIPSTUN() {
            externalIP = ip
            return ip
        }
        if let ip = try? await getExternalIPWebService() {
            externalIP = ip
            return ip
        }
        return nil
    }

    // MARK: - Mapping bookkeeping

    private func recordMapping(
        internal internalPort: UInt16,
        external externalPort: UInt16,
        proto: String,
        method: MappingMethod,
        leaseSeconds: UInt32
    ) {
        mappedPorts.append(InternalMapping(
            internalPort: internalPort,
            externalPort: externalPort,
            proto: proto,
            method: method,
            leaseSeconds: leaseSeconds,
            createdAt: Date()
        ))
        if leaseSeconds > 0 {
            ensureRefreshRunning()
        }
    }

    private func ensureRefreshRunning() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = await self?.nextRefreshDelay() ?? 1800
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { break }
                await self?.refreshAllMappings()
            }
        }
    }

    /// Half the shortest active finite lease, floored at 60s. If we only have
    /// permanent mappings (or none), falls back to 1800s — permanent mappings
    /// don't need refresh, but the loop still ticks to pick up newly-added
    /// finite-lease mappings without a wake signal.
    private func nextRefreshDelay() -> Int {
        let finiteLeases = mappedPorts.compactMap { $0.leaseSeconds > 0 ? Int($0.leaseSeconds) : nil }
        guard let shortest = finiteLeases.min() else { return 1800 }
        return max(60, shortest / 2)
    }

    private func refreshAllMappings() async {
        guard !mappedPorts.isEmpty else { return }
        logger.debug("Refreshing \(self.mappedPorts.count) port mappings")

        // Work off a snapshot; iterate indices so we can update createdAt in place.
        let indices = mappedPorts.indices.filter { mappedPorts[$0].leaseSeconds > 0 }
        for idx in indices {
            let mapping = mappedPorts[idx]
            do {
                switch mapping.method {
                case .upnp:
                    _ = try await mapPortUPnPWithFallback(
                        mapping.internalPort,
                        externalPort: mapping.externalPort,
                        protocol: mapping.proto
                    )
                case .natpmp:
                    _ = try await mapPortNATPMPRaw(
                        mapping.internalPort,
                        externalPort: mapping.externalPort,
                        protocol: mapping.proto,
                        lifetime: mapping.leaseSeconds
                    )
                }
                if idx < mappedPorts.count {
                    mappedPorts[idx].createdAt = Date()
                }
                logger.debug("Refreshed \(mapping.proto) \(mapping.internalPort)->\(mapping.externalPort)")
            } catch {
                logger.warning("Mapping refresh failed for \(mapping.proto) \(mapping.externalPort): \(error.localizedDescription)")
                if case .upnp = mapping.method {
                    // Force rediscovery — gateway may have rebooted or changed.
                    cachedGateway = nil
                }
            }
        }
    }

    // MARK: - UPnP: mapping

    /// Prefers a finite lease (3600s). If the router rejects it with error 725
    /// (`OnlyPermanentLeasesSupported` — miniupnpd's default), retries with
    /// lease=0 and returns that.
    private func mapPortUPnPWithFallback(_ internalPort: UInt16, externalPort: UInt16, protocol proto: String) async throws -> (port: UInt16, lease: UInt32) {
        do {
            let port = try await mapPortUPnPRaw(internalPort, externalPort: externalPort, protocol: proto, lease: 3600)
            return (port, 3600)
        } catch NATError.soapFault(code: 725) {
            logger.debug("Router rejected finite lease (725), retrying with permanent lease")
            let port = try await mapPortUPnPRaw(internalPort, externalPort: externalPort, protocol: proto, lease: 0)
            return (port, 0)
        }
    }

    private func mapPortUPnPRaw(_ internalPort: UInt16, externalPort: UInt16, protocol proto: String, lease: UInt32) async throws -> UInt16 {
        let gateway = try await resolveUPnPGateway()
        gatewayIP = gateway.ip

        guard let localIP = Self.localInterfaceIP() else {
            logger.error("Could not determine local IP address")
            throw NATError.noLocalIP
        }

        logger.debug("Local IP \(localIP), gateway \(gateway.ip), sending AddPortMapping (lease \(lease)) to \(gateway.controlURL)")

        let body = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:AddPortMapping xmlns:u="\(gateway.serviceType)">
                    <NewRemoteHost></NewRemoteHost>
                    <NewExternalPort>\(externalPort)</NewExternalPort>
                    <NewProtocol>\(proto)</NewProtocol>
                    <NewInternalPort>\(internalPort)</NewInternalPort>
                    <NewInternalClient>\(localIP)</NewInternalClient>
                    <NewEnabled>1</NewEnabled>
                    <NewPortMappingDescription>SeeleSeek</NewPortMappingDescription>
                    <NewLeaseDuration>\(lease)</NewLeaseDuration>
                </u:AddPortMapping>
            </s:Body>
        </s:Envelope>
        """

        _ = try await sendUPnPRequest(
            to: gateway.controlURL,
            serviceType: gateway.serviceType,
            action: "AddPortMapping",
            body: body
        )
        logger.info("AddPortMapping succeeded for port \(externalPort)")
        return externalPort
    }

    private func getExternalIPUPnP() async throws -> String {
        let gateway = try await resolveUPnPGateway()
        gatewayIP = gateway.ip

        let body = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:GetExternalIPAddress xmlns:u="\(gateway.serviceType)">
                </u:GetExternalIPAddress>
            </s:Body>
        </s:Envelope>
        """

        let response = try await sendUPnPRequest(
            to: gateway.controlURL,
            serviceType: gateway.serviceType,
            action: "GetExternalIPAddress",
            body: body
        )
        guard let ip = Self.parseExternalIP(from: response) else {
            throw NATError.ipDiscoveryFailed
        }
        return ip
    }

    private func removePortMappingUPnP(_ externalPort: UInt16, protocol proto: String) async throws {
        let gateway = try await resolveUPnPGateway()

        let body = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:DeletePortMapping xmlns:u="\(gateway.serviceType)">
                    <NewRemoteHost></NewRemoteHost>
                    <NewExternalPort>\(externalPort)</NewExternalPort>
                    <NewProtocol>\(proto)</NewProtocol>
                </u:DeletePortMapping>
            </s:Body>
        </s:Envelope>
        """

        _ = try? await sendUPnPRequest(
            to: gateway.controlURL,
            serviceType: gateway.serviceType,
            action: "DeletePortMapping",
            body: body
        )
    }

    // MARK: - UPnP: gateway discovery

    private func resolveUPnPGateway() async throws -> UPnPGateway {
        if let cached = cachedGateway, cached.isValid {
            return cached.gateway
        }
        let fresh = try await discoverUPnPGateway()
        cachedGateway = CachedGateway(gateway: fresh, cachedAt: Date())
        return fresh
    }

    private func discoverUPnPGateway() async throws -> UPnPGateway {
        logger.debug("Discovering UPnP gateway via SSDP")
        // A single probe for InternetGatewayDevice:1 catches essentially every
        // consumer IGD. We used to probe WANIPConnection:1 as well after a 500ms
        // wait, but the second probe almost never adds coverage — just latency.
        return try await discoverGatewayWithServiceType("urn:schemas-upnp-org:device:InternetGatewayDevice:1")
    }

    /// SSDP M-SEARCH via `NWConnection`. Note: `NWConnectionGroup` +
    /// `NWMulticastGroup` is the documented multicast path, but the
    /// unicast-reply-to-multicast-send pattern `NWConnection` gives us works
    /// in practice on macOS and a rewrite would risk macOS-version regressions
    /// with no correctness gain.
    private func discoverGatewayWithServiceType(_ serviceType: String) async throws -> UPnPGateway {
        // MX=2 gives routers realistic think time. Must use CRLF endings.
        let ssdpRequest = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(serviceType)\r\n\r\n"

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let endpoint = NWEndpoint.hostPort(host: "239.255.255.250", port: 1900)
        let connection = NWConnection(to: endpoint, using: params)

        let didComplete = Mutex(false)

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    connection.send(content: ssdpRequest.data(using: .utf8), completion: .contentProcessed { [logger] error in
                        if let error = error {
                            logger.warning("SSDP send error: \(error.localizedDescription)")
                        }
                    })

                    @Sendable func receiveNext() {
                        connection.receiveMessage { data, _, _, error in
                            guard !didComplete.withLock({ $0 }) else { return }

                            if let data = data, let response = String(data: data, encoding: .utf8) {
                                self.logger.debug("SSDP response (\(data.count) bytes)")
                                if let location = Self.parseLocationHeader(from: response) {
                                    self.logger.debug("Gateway at \(location)")
                                    let taskConnection = connection
                                    let taskContinuation = continuation
                                    Task { @Sendable in
                                        do {
                                            let gateway = try await self.fetchGatewayInfo(from: location)
                                            guard didComplete.withLock({
                                                guard !$0 else { return false }
                                                $0 = true
                                                return true
                                            }) else { return }
                                            taskConnection.cancel()
                                            taskContinuation.resume(returning: gateway)
                                        } catch {
                                            receiveNext()
                                        }
                                    }
                                } else {
                                    receiveNext()
                                }
                            } else if error != nil {
                                // Errors mid-stream shouldn't kill discovery; let timeout fire.
                            } else {
                                receiveNext()
                            }
                        }
                    }
                    receiveNext()

                case .failed(let error):
                    guard didComplete.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(throwing: error)

                default:
                    break
                }
            }

            connection.start(queue: .global())

            let timeoutConnection = connection
            let timeoutContinuation = continuation
            Task { @Sendable in
                try? await Task.sleep(for: .milliseconds(1500))
                guard didComplete.withLock({
                    guard !$0 else { return false }
                    $0 = true
                    return true
                }) else { return }
                timeoutConnection.cancel()
                timeoutContinuation.resume(throwing: NATError.discoveryTimeout)
            }
        }
    }

    private func fetchGatewayInfo(from location: String) async throws -> UPnPGateway {
        guard let url = URL(string: location) else {
            throw NATError.invalidGatewayURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw NATError.invalidGatewayResponse
        }
        guard let match = Self.parseControlURL(from: xml, baseURL: location) else {
            logger.warning("No WAN*Connection service found in device description")
            throw NATError.noControlURL
        }
        logger.debug("Selected \(match.serviceType) at \(match.controlURL)")
        return UPnPGateway(
            ip: url.host ?? "",
            controlURL: match.controlURL,
            serviceType: match.serviceType
        )
    }

    // MARK: - UPnP: XML / SOAP

    /// Walks `<service>` blocks, matches `<serviceType>` against the preferred
    /// WAN*Connection types, and resolves `<controlURL>` against `<URLBase>`
    /// (or the LOCATION URL) preserving any non-default port.
    nonisolated static func parseControlURL(from xml: String, baseURL: String) -> (controlURL: String, serviceType: String)? {
        var base: URL? = URL(string: baseURL)
        if let urlBase = firstCaptured(pattern: #"<URLBase>([^<]+)</URLBase>"#, in: xml),
           let parsed = URL(string: urlBase.trimmingCharacters(in: .whitespacesAndNewlines)) {
            base = parsed
        }

        // Priority order — newer versions first, PPP last.
        let preferredTypes = [
            "urn:schemas-upnp-org:service:WANIPConnection:2",
            "urn:schemas-upnp-org:service:WANIPConnection:1",
            "urn:schemas-upnp-org:service:WANPPPConnection:1"
        ]

        let services = allCaptured(pattern: #"<service\b[^>]*>(.*?)</service>"#, in: xml)
        var candidates: [(type: String, controlURL: String)] = []
        for service in services {
            guard
                let type = firstCaptured(pattern: #"<serviceType>([^<]+)</serviceType>"#, in: service)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                let control = firstCaptured(pattern: #"<controlURL>([^<]+)</controlURL>"#, in: service)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else { continue }
            candidates.append((type, control))
        }

        for wanted in preferredTypes {
            if let hit = candidates.first(where: { $0.type == wanted }),
               let resolved = resolveURL(hit.controlURL, relativeTo: base) {
                return (resolved, wanted)
            }
        }
        return nil
    }

    private nonisolated static func resolveURL(_ path: String, relativeTo base: URL?) -> String? {
        let lower = path.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return path
        }
        // URL(string:relativeTo:) preserves scheme, host, AND port from the base.
        return URL(string: path, relativeTo: base)?.absoluteString
    }

    private nonisolated static func firstCaptured(pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: string) else { return nil }
        return String(string[captured])
    }

    private nonisolated static func allCaptured(pattern: String, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match -> String? in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: string) else { return nil }
            return String(string[r])
        }
    }

    nonisolated static func parseLocationHeader(from response: String) -> String? {
        for line in response.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("location:") {
                return line.dropFirst(9).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private nonisolated static func parseExternalIP(from response: String) -> String? {
        firstCaptured(pattern: #"<NewExternalIPAddress>([^<]+)</NewExternalIPAddress>"#, in: response)
    }

    /// Returns the response body on success. Throws `NATError.soapFault(code:)`
    /// when the body carries a UPnP fault — SOAP faults can come back on HTTP
    /// 200 *or* 5xx, so we check the body regardless of status code.
    @discardableResult
    private func sendUPnPRequest(to controlURL: String, serviceType: String, action: String, body: String) async throws -> String {
        guard let url = URL(string: controlURL) else {
            throw NATError.invalidGatewayURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let responseString = String(data: data, encoding: .utf8) ?? ""
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.debug("UPnP \(action) response: HTTP \(statusCode)")

        if let code = Self.parseSOAPFaultCode(from: responseString) {
            logger.warning("UPnP \(action) SOAP fault: code=\(code)")
            throw NATError.soapFault(code: code)
        }

        guard statusCode == 200 else {
            logger.warning("UPnP \(action) HTTP \(statusCode), body: \(responseString.prefix(500))")
            throw NATError.invalidGatewayResponse
        }

        return responseString
    }

    private nonisolated static func parseSOAPFaultCode(from response: String) -> Int? {
        // Preferred: nested <UPnPError><errorCode>NNN</errorCode></UPnPError>
        if let upnpErr = firstCaptured(pattern: #"<UPnPError\b[^>]*>(.*?)</UPnPError>"#, in: response),
           let codeStr = firstCaptured(pattern: #"<errorCode>(\d+)</errorCode>"#, in: upnpErr),
           let code = Int(codeStr) {
            return code
        }
        // Some routers wrap a generic fault without UPnPError — still signal failure.
        let hasFault = response.range(of: "<s:Fault", options: .caseInsensitive) != nil
            || response.range(of: "<SOAP-ENV:Fault", options: .caseInsensitive) != nil
        if hasFault {
            if let codeStr = firstCaptured(pattern: #"<errorCode>(\d+)</errorCode>"#, in: response),
               let code = Int(codeStr) {
                return code
            }
            return -1
        }
        return nil
    }

    // MARK: - NAT-PMP

    /// Single entry point for NAT-PMP mapping, unmapping, and refresh.
    /// - `lifetime: 0` + `externalPort: 0` is RFC 6886 §3.3's delete request.
    private func mapPortNATPMPRaw(_ internalPort: UInt16, externalPort: UInt16, protocol proto: String, lifetime: UInt32) async throws -> UInt16 {
        guard let gateway = Self.getDefaultGateway() else {
            throw NATError.noGatewayFound
        }
        // Keep diagnostics state in sync even when UPnP wasn't used.
        gatewayIP = gateway

        let opcode: UInt8 = proto.uppercased() == "TCP" ? 2 : 1
        let expectedResponseOpcode = opcode + 128

        // NAT-PMP is network byte order (RFC 6886); use the BE helpers, not the Soulseek LE ones.
        let request: Data = {
            var data = Data()
            data.append(0)              // Version
            data.append(opcode)         // Opcode: 1=UDP, 2=TCP
            data.append(contentsOf: [0, 0])  // Reserved
            data.appendUInt16BE(internalPort)
            data.appendUInt16BE(externalPort)
            data.appendUInt32BE(lifetime)
            return data
        }()

        let params = NWParameters.udp
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(gateway), port: 5351)
        let connection = NWConnection(to: endpoint, using: params)
        let didComplete = Mutex(false)

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { _ in })

                    connection.receiveMessage { data, _, _, _ in
                        guard let data = data, data.count >= 16 else { return }

                        let respVersion = data.readByte(at: 0) ?? 0xFF
                        let respOpcode = data.readByte(at: 1) ?? 0
                        let resultCode = data.readUInt16BE(at: 2) ?? 0xFFFF
                        let mappedPort = data.readUInt16BE(at: 10) ?? 0

                        guard didComplete.withLock({
                            guard !$0 else { return false }
                            $0 = true
                            return true
                        }) else { return }
                        connection.cancel()

                        // RFC 6886: response version must echo request version (0) and
                        // opcode must be request_opcode + 128.
                        guard respVersion == 0, respOpcode == expectedResponseOpcode else {
                            continuation.resume(throwing: NATError.mappingFailed)
                            return
                        }

                        if lifetime == 0 {
                            // Unmap: success is just resultCode==0.
                            if resultCode == 0 {
                                continuation.resume(returning: 0)
                            } else {
                                continuation.resume(throwing: NATError.natpmpError(code: resultCode))
                            }
                        } else {
                            if resultCode == 0 && mappedPort > 0 {
                                continuation.resume(returning: mappedPort)
                            } else {
                                continuation.resume(throwing: NATError.natpmpError(code: resultCode))
                            }
                        }
                    }

                case .failed(let error):
                    guard didComplete.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(throwing: error)

                default:
                    break
                }
            }

            connection.start(queue: .global())

            let timeoutConnection = connection
            let timeoutContinuation = continuation
            Task { @Sendable in
                try? await Task.sleep(for: .seconds(1))
                guard didComplete.withLock({
                    guard !$0 else { return false }
                    $0 = true
                    return true
                }) else { return }
                timeoutConnection.cancel()
                timeoutContinuation.resume(throwing: NATError.discoveryTimeout)
            }
        }
    }

    private func removePortMappingNATPMP(_ internalPort: UInt16, protocol proto: String) async throws {
        _ = try await mapPortNATPMPRaw(internalPort, externalPort: 0, protocol: proto, lifetime: 0)
    }

    // MARK: - STUN

    private func getExternalIPSTUN() async throws -> String {
        // Cloudflare first (fast, permissive rate limits), Google/Nextcloud as fallbacks.
        let servers: [(host: String, port: UInt16)] = [
            ("stun.cloudflare.com", 3478),
            ("stun.l.google.com", 19302),
            ("stun1.l.google.com", 19302),
            ("stun.nextcloud.com", 3478)
        ]
        for server in servers {
            if let ip = try? await stunQuery(host: server.host, port: server.port) {
                return ip
            }
        }
        throw NATError.ipDiscoveryFailed
    }

    private func stunQuery(host: String, port: UInt16) async throws -> String {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NATError.ipDiscoveryFailed
        }
        // Force IPv4: Soulseek peer addresses are 32-bit on the wire, so the
        // IPv6 reflexive address from a dual-stack path is useless for us.
        let params = NWParameters.udp
        if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let connection = NWConnection(to: endpoint, using: params)

        // 96-bit transaction ID. Captured so we can reject late/injected replies
        // that don't match this specific query.
        let txnID: (UInt32, UInt32, UInt32) = (
            UInt32.random(in: 0...UInt32.max),
            UInt32.random(in: 0...UInt32.max),
            UInt32.random(in: 0...UInt32.max)
        )

        // STUN is network byte order; don't use the Soulseek LE `append*` helpers here.
        let request: Data = {
            var data = Data()
            data.appendUInt16BE(0x0001) // Binding Request
            data.appendUInt16BE(0x0000) // Message Length
            data.appendUInt32BE(0x2112A442) // Magic Cookie
            data.appendUInt32BE(txnID.0)
            data.appendUInt32BE(txnID.1)
            data.appendUInt32BE(txnID.2)
            return data
        }()

        let didComplete = Mutex(false)
        let queryLogger = logger

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { _ in })

                    connection.receiveMessage { data, _, _, _ in
                        guard let data, data.count >= 20 else { return }
                        // Drop replies whose transaction ID doesn't match ours — guards
                        // against stale responses from prior queries to the same server.
                        guard data.readUInt32BE(at: 8) == txnID.0,
                              data.readUInt32BE(at: 12) == txnID.1,
                              data.readUInt32BE(at: 16) == txnID.2 else { return }

                        if let reflex = Self.parseSTUNResponse(data) {
                            guard didComplete.withLock({
                                guard !$0 else { return false }
                                $0 = true
                                return true
                            }) else { return }
                            connection.cancel()
                            continuation.resume(returning: reflex.ip)
                        } else {
                            queryLogger.debug("STUN \(host):\(port) parse failed; bytes: \(data.hexString)")
                        }
                    }

                case .failed(let error):
                    guard didComplete.withLock({
                        guard !$0 else { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(throwing: error)

                default:
                    break
                }
            }

            connection.start(queue: .global())

            let timeoutConnection = connection
            let timeoutContinuation = continuation
            Task { @Sendable in
                try? await Task.sleep(for: .seconds(2))
                guard didComplete.withLock({
                    guard !$0 else { return false }
                    $0 = true
                    return true
                }) else { return }
                timeoutConnection.cancel()
                timeoutContinuation.resume(throwing: NATError.discoveryTimeout)
            }
        }
    }

    /// Parses a STUN Binding Response's XOR-MAPPED-ADDRESS attribute. Returns
    /// the reflexive IP and port. The port is useful for NAT-classification
    /// diagnostics (e.g. distinguishing symmetric NAT by comparing reflexive
    /// ports across two different STUN servers).
    nonisolated static func parseSTUNResponse(_ data: Data) -> (ip: String, port: UInt16)? {
        guard data.count >= 20 else { return nil }
        var offset = 20
        while offset + 4 <= data.count {
            guard let attrType = data.readUInt16BE(at: offset),
                  let attrLength = data.readUInt16BE(at: offset + 2) else {
                break
            }

            if attrType == 0x0020 && attrLength >= 8 {
                let family = data.readByte(at: offset + 5)
                if family == 0x01,
                   let xorPort = data.readUInt16BE(at: offset + 6),
                   let xorIP = data.readUInt32BE(at: offset + 8) {
                    // Port is XOR'd with the high 16 bits of the magic cookie.
                    let port = xorPort ^ 0x2112
                    // Address is XOR'd with the full magic cookie.
                    let ip = xorIP ^ 0x2112A442
                    let b1 = (ip >> 24) & 0xFF
                    let b2 = (ip >> 16) & 0xFF
                    let b3 = (ip >> 8) & 0xFF
                    let b4 = ip & 0xFF
                    return ("\(b1).\(b2).\(b3).\(b4)", port)
                }
            }

            offset += 4 + Int(attrLength)
            if attrLength % 4 != 0 {
                offset += 4 - Int(attrLength % 4)
            }
        }
        return nil
    }

    // MARK: - Web Service Fallback

    private func getExternalIPWebService() async throws -> String {
        let urls = [
            "https://api.ipify.org",
            "https://ifconfig.me/ip",
            "https://icanhazip.com"
        ]
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return ip
                }
            } catch {
                continue
            }
        }
        throw NATError.ipDiscoveryFailed
    }

    // MARK: - Local networking

    /// Primary IPv4 address for the machine. Enumerates all interfaces, filters
    /// loopback / link-local / VPN / AWDL / Low-Latency Wireless, and prefers
    /// `en0`/`en1` when present. Package-internal so NetworkClient can share it.
    static func localInterfaceIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferred: String?
        var fallback: String?

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee,
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let flags = interface.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0,
                  (flags & UInt32(IFF_RUNNING)) != 0,
                  (flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }

            let name = String(validatingCString: interface.ifa_name) ?? ""
            if name.hasPrefix("utun") || name.hasPrefix("ipsec")
                || name.hasPrefix("awdl") || name.hasPrefix("llw") {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST
            )
            let bytes = hostname.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            let ip = String(decoding: bytes, as: UTF8.self)

            guard !ip.isEmpty, !ip.hasPrefix("169.254.") else { continue }

            if name == "en0" || name == "en1" {
                if preferred == nil { preferred = ip }
            } else if fallback == nil {
                fallback = ip
            }
        }
        return preferred ?? fallback
    }

    /// Currently-active default IPv4 gateway via SystemConfiguration's
    /// `State:/Network/Global/IPv4` dictionary. Falls back to the `.1` on /24
    /// heuristic if SC lookup fails.
    static func getDefaultGateway() -> String? {
        if let store = SCDynamicStoreCreate(nil, "com.seeleseek.NATService" as CFString, nil, nil),
           let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let router = value["Router"] as? String {
            return router
        }

        if let localIP = localInterfaceIP() {
            let parts = localIP.split(separator: ".")
            if parts.count == 4 {
                return "\(parts[0]).\(parts[1]).\(parts[2]).1"
            }
        }
        return nil
    }
}

// MARK: - Errors

enum NATError: Error, LocalizedError {
    case noGatewayFound
    case noLocalIP
    case mappingFailed
    case discoveryTimeout
    case invalidGatewayURL
    case invalidGatewayResponse
    case noControlURL
    case ipDiscoveryFailed
    case soapFault(code: Int)
    case natpmpError(code: UInt16)

    public var errorDescription: String? {
        switch self {
        case .noGatewayFound: return "No UPnP gateway found"
        case .noLocalIP: return "Could not determine local IP address"
        case .mappingFailed: return "Port mapping failed"
        case .discoveryTimeout: return "Gateway discovery timed out"
        case .invalidGatewayURL: return "Invalid gateway URL"
        case .invalidGatewayResponse: return "Invalid gateway response"
        case .noControlURL: return "No control URL found"
        case .ipDiscoveryFailed: return "Could not discover external IP"
        case .soapFault(let code): return "UPnP SOAP fault (code \(code))"
        case .natpmpError(let code): return "NAT-PMP error (code \(code))"
        }
    }
}

// Big-endian helpers scoped to this file — STUN (and NAT-PMP) are network byte
// order, unlike the Soulseek-LE `append*`/`read*` helpers in DataExtensions.swift.
private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    func readUInt16BE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { bytes in
            UInt16(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }

    func readUInt32BE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { bytes in
            UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }
}

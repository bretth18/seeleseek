import Foundation
import Network
import os
import Synchronization

/// Handles NAT traversal using UPnP and NAT-PMP
actor NATService {
    private let logger = Logger(subsystem: "com.seeleseek", category: "NATService")

    private var mappedPorts: [(internal: UInt16, external: UInt16, protocol: String)] = []
    private var externalIP: String?
    private var gatewayIP: String?

    // MARK: - Public Interface

    var externalAddress: String? { externalIP }

    /// Attempts to map a port using UPnP or NAT-PMP
    func mapPort(_ internalPort: UInt16, externalPort: UInt16? = nil, protocol proto: String = "TCP") async throws -> UInt16 {
        let targetExternal = externalPort ?? internalPort

        print("🔧 NAT: Attempting to map port \(internalPort) -> \(targetExternal) (\(proto))")

        // Try UPnP first
        do {
            let mapped = try await mapPortUPnP(internalPort, externalPort: targetExternal, protocol: proto)
            mappedPorts.append((internalPort, mapped, proto))
            print("✅ NAT: UPnP mapped port \(internalPort) -> \(mapped)")
            logger.info("UPnP mapped port \(internalPort) -> \(mapped)")
            Task { @MainActor in ActivityLog.shared.logNATMapping(port: mapped, success: true) }
            return mapped
        } catch {
            print("⚠️ NAT: UPnP failed: \(error)")
        }

        // Fall back to NAT-PMP
        do {
            let mapped = try await mapPortNATPMP(internalPort, externalPort: targetExternal, protocol: proto)
            mappedPorts.append((internalPort, mapped, proto))
            print("✅ NAT: NAT-PMP mapped port \(internalPort) -> \(mapped)")
            logger.info("NAT-PMP mapped port \(internalPort) -> \(mapped)")
            return mapped
        } catch {
            print("⚠️ NAT: NAT-PMP failed: \(error)")
        }

        // If both fail, assume we're not behind NAT or port is already open
        print("❌ NAT: All mapping methods failed for port \(internalPort)")
        logger.warning("NAT mapping failed for port \(internalPort), assuming direct connection")
        Task { @MainActor in ActivityLog.shared.logNATMapping(port: internalPort, success: false) }
        throw NATError.mappingFailed
    }

    /// Removes all port mappings
    func removeAllMappings() async {
        for mapping in mappedPorts {
            try? await removePortMapping(mapping.external, protocol: mapping.protocol)
        }
        mappedPorts.removeAll()
    }

    /// Discovers external IP address
    func discoverExternalIP() async -> String? {
        // Try UPnP first
        if let ip = try? await getExternalIPUPnP() {
            externalIP = ip
            return ip
        }

        // Try STUN
        if let ip = try? await getExternalIPSTUN() {
            externalIP = ip
            return ip
        }

        // Fall back to web service
        if let ip = try? await getExternalIPWebService() {
            externalIP = ip
            return ip
        }

        return nil
    }

    // MARK: - UPnP Implementation

    private func mapPortUPnP(_ internalPort: UInt16, externalPort: UInt16, protocol proto: String) async throws -> UInt16 {
        print("🔧 NAT: mapPortUPnP starting...")

        // Discover UPnP gateway
        let gateway = try await discoverUPnPGateway()
        gatewayIP = gateway.ip

        // Get local IP
        guard let localIP = getLocalIPAddress() else {
            print("❌ NAT: Could not determine local IP address")
            throw NATError.noLocalIP
        }

        print("🔧 NAT: Local IP: \(localIP), Gateway: \(gateway.ip)")
        print("🔧 NAT: Sending AddPortMapping request to \(gateway.controlURL)")

        // Send AddPortMapping request
        let soapAction = "AddPortMapping"
        let soapBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:AddPortMapping xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
                    <NewRemoteHost></NewRemoteHost>
                    <NewExternalPort>\(externalPort)</NewExternalPort>
                    <NewProtocol>\(proto)</NewProtocol>
                    <NewInternalPort>\(internalPort)</NewInternalPort>
                    <NewInternalClient>\(localIP)</NewInternalClient>
                    <NewEnabled>1</NewEnabled>
                    <NewPortMappingDescription>SeeleSeek</NewPortMappingDescription>
                    <NewLeaseDuration>0</NewLeaseDuration>
                </u:AddPortMapping>
            </s:Body>
        </s:Envelope>
        """

        let success = try await sendUPnPRequest(to: gateway.controlURL, action: soapAction, body: soapBody)

        if success {
            print("✅ NAT: AddPortMapping succeeded for port \(externalPort)")
            return externalPort
        }

        print("❌ NAT: AddPortMapping failed")
        throw NATError.mappingFailed
    }

    private func getExternalIPUPnP() async throws -> String {
        guard let gateway = try? await discoverUPnPGateway() else {
            throw NATError.noGatewayFound
        }

        let soapAction = "GetExternalIPAddress"
        let soapBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:GetExternalIPAddress xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
                </u:GetExternalIPAddress>
            </s:Body>
        </s:Envelope>
        """

        guard let response = try? await sendUPnPRequestWithResponse(to: gateway.controlURL, action: soapAction, body: soapBody),
              let ip = parseExternalIP(from: response) else {
            throw NATError.ipDiscoveryFailed
        }

        return ip
    }

    private func removePortMapping(_ externalPort: UInt16, protocol proto: String) async throws {
        guard let gateway = try? await discoverUPnPGateway() else { return }

        let soapAction = "DeletePortMapping"
        let soapBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:DeletePortMapping xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
                    <NewRemoteHost></NewRemoteHost>
                    <NewExternalPort>\(externalPort)</NewExternalPort>
                    <NewProtocol>\(proto)</NewProtocol>
                </u:DeletePortMapping>
            </s:Body>
        </s:Envelope>
        """

        _ = try? await sendUPnPRequest(to: gateway.controlURL, action: soapAction, body: soapBody)
    }

    private struct UPnPGateway {
        let ip: String
        let controlURL: String
    }

    private func discoverUPnPGateway() async throws -> UPnPGateway {
        print("🔧 NAT: Discovering UPnP gateway via SSDP...")

        // Try the most common service types first - avoid rapid-fire probing that triggers IDS
        // Most routers respond to InternetGatewayDevice:1
        let serviceTypes = [
            "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
            "urn:schemas-upnp-org:service:WANIPConnection:1"
        ]

        for (index, serviceType) in serviceTypes.enumerated() {
            // Add delay between probes to avoid triggering IDS (except for first one)
            if index > 0 {
                try? await Task.sleep(for: .milliseconds(500))
            }

            print("🔧 NAT: Trying service type: \(serviceType)")
            if let gateway = try? await discoverGatewayWithServiceType(serviceType) {
                return gateway
            }
        }

        throw NATError.noGatewayFound
    }

    private func discoverGatewayWithServiceType(_ serviceType: String) async throws -> UPnPGateway {
        // SSDP M-SEARCH request - must use proper CRLF line endings
        let ssdpRequest = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(serviceType)\r\n\r\n"

        // Create UDP connection group for multicast - allows receiving from any source
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        // Create a UDP connection to send the multicast request
        let endpoint = NWEndpoint.hostPort(host: "239.255.255.250", port: 1900)
        let connection = NWConnection(to: endpoint, using: params)

        let didComplete = Mutex(false)

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    // Send the M-SEARCH request
                    connection.send(content: ssdpRequest.data(using: .utf8), completion: .contentProcessed { error in
                        if let error = error {
                            print("🔧 NAT: SSDP send error: \(error)")
                        }
                    })

                    // Receive response - NWConnection CAN receive unicast replies to multicast requests
                    @Sendable func receiveNext() {
                        connection.receiveMessage { data, context, _, error in
                            guard !didComplete.withLock({ $0 }) else { return }

                            if let data = data, let response = String(data: data, encoding: .utf8) {
                                print("🔧 NAT: SSDP response (\(data.count) bytes)")

                                if let location = self?.parseLocationHeader(from: response) {
                                    print("🔧 NAT: Gateway at: \(location)")

                                    Task { [weak self] in
                                        do {
                                            let gateway = try await self?.fetchGatewayInfo(from: location)
                                            if let gateway = gateway {
                                                guard didComplete.withLock({
                                                    guard !$0 else { return false }
                                                    $0 = true
                                                    return true
                                                }) else { return }
                                                connection.cancel()
                                                continuation.resume(returning: gateway)
                                            }
                                        } catch {
                                            // Try next response
                                            receiveNext()
                                        }
                                    }
                                } else {
                                    // No location header, try next response
                                    receiveNext()
                                }
                            } else if error != nil {
                                // Error receiving, but don't fail yet - wait for timeout
                            } else {
                                // No data, try next
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

            // Timeout after 1.5 seconds
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                guard didComplete.withLock({
                    guard !$0 else { return false }
                    $0 = true
                    return true
                }) else { return }
                connection.cancel()
                continuation.resume(throwing: NATError.discoveryTimeout)
            }
        }
    }

    private nonisolated func parseLocationHeader(from response: String) -> String? {
        let lines = response.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("location:") {
                return line.dropFirst(9).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func fetchGatewayInfo(from location: String) async throws -> UPnPGateway {
        guard let url = URL(string: location) else {
            throw NATError.invalidGatewayURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw NATError.invalidGatewayResponse
        }

        // Parse control URL from device description
        // This is simplified - real implementation would use XML parser
        if let controlURL = parseControlURL(from: xml, baseURL: location) {
            return UPnPGateway(ip: url.host ?? "", controlURL: controlURL)
        }

        throw NATError.noControlURL
    }

    private func parseControlURL(from xml: String, baseURL: String) -> String? {
        // Look for WANIPConnection service
        if let range = xml.range(of: "<controlURL>"),
           let endRange = xml.range(of: "</controlURL>", range: range.upperBound..<xml.endIndex) {
            let urlPath = String(xml[range.upperBound..<endRange.lowerBound])

            // Make absolute URL
            if urlPath.hasPrefix("http") {
                return urlPath
            } else if let base = URL(string: baseURL) {
                return "\(base.scheme ?? "http")://\(base.host ?? "")\(urlPath)"
            }
        }
        return nil
    }

    private func sendUPnPRequest(to controlURL: String, action: String, body: String) async throws -> Bool {
        guard let url = URL(string: controlURL) else {
            throw NATError.invalidGatewayURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:WANIPConnection:1#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("🔧 NAT: UPnP \(action) response: HTTP \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    if let responseBody = String(data: data, encoding: .utf8) {
                        print("🔧 NAT: Error response: \(responseBody.prefix(500))")
                    }
                }
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            print("🔧 NAT: UPnP request error: \(error)")
            throw error
        }
    }

    private func sendUPnPRequestWithResponse(to controlURL: String, action: String, body: String) async throws -> String {
        guard let url = URL(string: controlURL) else {
            throw NATError.invalidGatewayURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:WANIPConnection:1#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let response = String(data: data, encoding: .utf8) else {
            throw NATError.invalidGatewayResponse
        }

        return response
    }

    private func parseExternalIP(from response: String) -> String? {
        if let range = response.range(of: "<NewExternalIPAddress>"),
           let endRange = response.range(of: "</NewExternalIPAddress>", range: range.upperBound..<response.endIndex) {
            return String(response[range.upperBound..<endRange.lowerBound])
        }
        return nil
    }

    // MARK: - NAT-PMP Implementation

    private func mapPortNATPMP(_ internalPort: UInt16, externalPort: UInt16, protocol proto: String) async throws -> UInt16 {
        guard let gatewayIP = getDefaultGateway() else {
            throw NATError.noGatewayFound
        }

        // NAT-PMP uses UDP port 5351
        let params = NWParameters.udp
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(gatewayIP), port: 5351)
        let connection = NWConnection(to: endpoint, using: params)

        // Build NAT-PMP request
        let request: Data = {
            var data = Data()
            data.append(0) // Version
            data.append(proto == "TCP" ? 2 : 1) // Opcode: 1=UDP, 2=TCP
            data.append(contentsOf: [0, 0]) // Reserved
            data.appendUInt16(internalPort)
            data.appendUInt16(externalPort)
            data.appendUInt32(7200) // Lifetime in seconds
            return data
        }()

        let didComplete = Mutex(false)

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { _ in })

                    connection.receiveMessage { data, _, _, error in
                        guard let data = data, data.count >= 16 else { return }

                        // Parse response
                        let resultCode = data.readUInt16(at: 2) ?? 0xFFFF
                        let mappedPort = data.readUInt16(at: 10) ?? 0

                        guard didComplete.withLock({
                            guard !$0 else { return false }
                            $0 = true
                            return true
                        }) else { return }
                        connection.cancel()

                        if resultCode == 0 && mappedPort > 0 {
                            continuation.resume(returning: mappedPort)
                        } else {
                            continuation.resume(throwing: NATError.mappingFailed)
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

            Task {
                try? await Task.sleep(for: .seconds(1))
                guard didComplete.withLock({
                    guard !$0 else { return false }
                    $0 = true
                    return true
                }) else { return }
                connection.cancel()
                continuation.resume(throwing: NATError.discoveryTimeout)
            }
        }
    }

    // MARK: - STUN Implementation

    private func getExternalIPSTUN() async throws -> String {
        // Use Google's STUN server
        let params = NWParameters.udp
        let endpoint = NWEndpoint.hostPort(host: "stun.l.google.com", port: 19302)
        let connection = NWConnection(to: endpoint, using: params)

        // STUN Binding Request
        let request: Data = {
            var data = Data()
            data.appendUInt16(0x0001) // Binding Request
            data.appendUInt16(0x0000) // Message Length
            data.appendUInt32(0x2112A442) // Magic Cookie
            // Transaction ID (12 bytes)
            for _ in 0..<3 {
                data.appendUInt32(UInt32.random(in: 0...UInt32.max))
            }
            return data
        }()

        let didComplete = Mutex(false)

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { _ in })

                    connection.receiveMessage { data, _, _, error in
                        guard let data = data else { return }

                        // Parse STUN response for XOR-MAPPED-ADDRESS
                        if let ip = self.parseSTUNResponse(data) {
                            guard didComplete.withLock({
                                guard !$0 else { return false }
                                $0 = true
                                return true
                            }) else { return }
                            connection.cancel()
                            continuation.resume(returning: ip)
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

            Task {
                try? await Task.sleep(for: .seconds(1))
                guard didComplete.withLock({
                    guard !$0 else { return false }
                    $0 = true
                    return true
                }) else { return }
                connection.cancel()
                continuation.resume(throwing: NATError.discoveryTimeout)
            }
        }
    }

    private nonisolated func parseSTUNResponse(_ data: Data) -> String? {
        guard data.count >= 20 else { return nil }

        // Skip header (20 bytes)
        var offset = 20

        while offset + 4 <= data.count {
            guard let attrType = data.readUInt16(at: offset),
                  let attrLength = data.readUInt16(at: offset + 2) else {
                break
            }

            // XOR-MAPPED-ADDRESS = 0x0020
            if attrType == 0x0020 && attrLength >= 8 {
                let family = data.readByte(at: offset + 5)
                if family == 0x01 { // IPv4
                    // XOR with magic cookie
                    guard data.readUInt16(at: offset + 6) != nil,
                          let xorIP = data.readUInt32(at: offset + 8) else {
                        break
                    }

                    let ip = xorIP ^ 0x2112A442
                    let b1 = (ip >> 24) & 0xFF
                    let b2 = (ip >> 16) & 0xFF
                    let b3 = (ip >> 8) & 0xFF
                    let b4 = ip & 0xFF

                    return "\(b1).\(b2).\(b3).\(b4)"
                }
            }

            offset += 4 + Int(attrLength)
            // Pad to 4-byte boundary
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

    // MARK: - Utility

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }

                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family

                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }

        return address
    }

    private func getDefaultGateway() -> String? {
        // Infer gateway from local IP address - most home routers use .1 on the subnet
        // This avoids spawning processes which can trigger security software
        if let localIP = getLocalIPAddress() {
            let parts = localIP.split(separator: ".")
            if parts.count == 4 {
                let gateway = "\(parts[0]).\(parts[1]).\(parts[2]).1"
                print("🔧 NAT: Inferred gateway from local IP: \(gateway)")
                return gateway
            }
        }

        print("🔧 NAT: Could not determine default gateway")
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

    var errorDescription: String? {
        switch self {
        case .noGatewayFound: return "No UPnP gateway found"
        case .noLocalIP: return "Could not determine local IP address"
        case .mappingFailed: return "Port mapping failed"
        case .discoveryTimeout: return "Gateway discovery timed out"
        case .invalidGatewayURL: return "Invalid gateway URL"
        case .invalidGatewayResponse: return "Invalid gateway response"
        case .noControlURL: return "No control URL found"
        case .ipDiscoveryFailed: return "Could not discover external IP"
        }
    }
}

// Required for getifaddrs
import Darwin

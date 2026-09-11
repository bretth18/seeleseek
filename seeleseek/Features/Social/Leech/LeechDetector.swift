import Foundation
import os
import SeeleseekCore

/// Modelled on Nicotine+'s Leech Detector. Server stats of 0/0 are
/// re-checked by browsing (the server reports zero for clients that have
/// not announced shares). Buddies are never probed. Flagged and messaged
/// users persist so a peer is messaged at most once, ever.
@Observable
@MainActor
final class LeechDetector: UploadPolicy {

    struct Services {
        var requestStats: @MainActor (String) async -> Void
        var browseShareCounts: @MainActor (String) async throws -> ShareCounts
        var sendPrivateMessage: @MainActor (_ username: String, _ text: String) -> Void
        var isBuddy: @MainActor (String) -> Bool
        var blockUser: @MainActor (String) async -> Void
        var log: @MainActor (_ title: String, _ detail: String, _ username: String) -> Void
        var loadSettings: @MainActor () async throws -> LeechSettings?
        var saveSettings: @MainActor (LeechSettings) async throws -> Void
        var loadNames: @MainActor (String) async throws -> [String]?
        var saveNames: @MainActor (_ key: String, _ names: [String]) async throws -> Void

        static let inert = Services(
            requestStats: { _ in },
            browseShareCounts: { _ in throw CancellationError() },
            sendPrivateMessage: { _, _ in },
            isBuddy: { _ in false },
            blockUser: { _ in },
            log: { _, _, _ in },
            loadSettings: { nil },
            saveSettings: { _ in },
            loadNames: { _ in nil },
            saveNames: { _, _ in }
        )
    }

    nonisolated struct ShareCounts: Equatable, Sendable {
        var files: UInt32
        var folders: UInt32
    }

    nonisolated enum Probe: Equatable {
        case requestingStats
        case verifyingShares
        case leecher
        case okay
    }

    var settings = LeechSettings() {
        didSet {
            isEnabled = settings.enabled
            guard !isLoading else { return }
            Task { await saveSettings() }
        }
    }
    /// Mirrors `settings.enabled` so upload rows observe this Bool, not
    /// every settings edit.
    private(set) var isEnabled = false
    private(set) var detectedLeechers: Set<String> = []
    private(set) var messagedLeechers: Set<String> = []
    private(set) var shareCounts: [String: ShareCounts] = [:]
    /// Past this a `.request` evaluation fails open; the start-stage
    /// re-check applies the verdict.
    var verdictTimeout: Duration = .seconds(3)

    @ObservationIgnored var services: Services
    @ObservationIgnored private(set) var probes: [String: Probe] = [:]
    @ObservationIgnored private var verdictWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    @ObservationIgnored private var verdictTimeouts: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.seeleseek", category: "LeechDetector")

    private static let detectedKey = "leechDetected"
    private static let messagedKey = "leechMessaged"

    init(services: Services = .inert) {
        self.services = services
    }

    func isLeecher(_ username: String) -> Bool {
        isEnabled && detectedLeechers.contains(username)
    }

    // MARK: - UploadPolicy

    @MainActor
    func evaluate(_ request: UploadPolicyRequest) async -> UploadPolicyDecision {
        guard settings.enabled else { return .allow }
        let user = request.username
        beginProbeIfNeeded(user)
        guard settings.action.deniesTransfers else { return .allow }
        if request.stage == .request, !detectedLeechers.contains(user) {
            await waitForVerdict(user)
        }
        return detectedLeechers.contains(user) ? .deny(reason: UploadDenialReason.notShared) : .allow
    }

    @MainActor
    func uploadDidComplete(username: String) async {
        guard settings.enabled, settings.action == .message, probes[username] == .leecher,
              messagedLeechers.insert(username).inserted else { return }
        persist(Self.messagedKey, messagedLeechers)
        let lines = settings.renderedMessage
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines {
            services.sendPrivateMessage(username, line)
        }
    }

    // MARK: - Probe

    func receivedStats(username: String, files: UInt32, folders: UInt32) {
        guard probes[username] == .requestingStats else { return }
        if files == 0 && folders == 0 {
            probes[username] = .verifyingShares
            Task { await verifyByBrowsing(username) }
            return
        }
        conclude(username, counts: ShareCounts(files: files, folders: folders))
    }

    private func verifyByBrowsing(_ username: String) async {
        // Unreachable or empty reply: the server's zero stands.
        let counts = (try? await services.browseShareCounts(username)) ?? ShareCounts(files: 0, folders: 0)
        guard probes[username] == .verifyingShares else { return }
        conclude(username, counts: counts)
    }

    private func beginProbeIfNeeded(_ username: String) {
        guard probes[username] == nil else { return }
        if services.isBuddy(username) {
            probes[username] = .okay
            unflag(username)
            return
        }
        probes[username] = .requestingStats
        Task { await services.requestStats(username) }
    }

    private func conclude(_ username: String, counts: ShareCounts) {
        if counts.files < settings.minSharedFiles || counts.folders < settings.minSharedFolders {
            probes[username] = .leecher
            shareCounts[username] = counts
            if detectedLeechers.insert(username).inserted {
                persist(Self.detectedKey, detectedLeechers)
            }
            logger.info("Leech detected: \(username) (\(counts.files) files, \(counts.folders) folders)")
            services.log(
                "Leech detected: \(username)",
                "Sharing \(counts.files) files in \(counts.folders) folders (minimum \(settings.minSharedFiles) files, \(settings.minSharedFolders) folders)",
                username
            )
            if settings.action == .block {
                Task { await services.blockUser(username) }
            }
        } else {
            probes[username] = .okay
            unflag(username)
        }
        resolveVerdictWaiters(username)
    }

    private func unflag(_ username: String) {
        shareCounts[username] = nil
        if detectedLeechers.remove(username) != nil {
            persist(Self.detectedKey, detectedLeechers)
        }
    }

    private func waitForVerdict(_ username: String) async {
        guard probes[username] == .requestingStats || probes[username] == .verifyingShares else { return }
        if verdictTimeouts[username] == nil {
            let timeout = verdictTimeout
            verdictTimeouts[username] = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.resolveVerdictWaiters(username)
            }
        }
        await withCheckedContinuation { verdictWaiters[username, default: []].append($0) }
    }

    private func resolveVerdictWaiters(_ username: String) {
        verdictTimeouts.removeValue(forKey: username)?.cancel()
        verdictWaiters.removeValue(forKey: username)?.forEach { $0.resume() }
    }

    // MARK: - Manual actions

    func block(_ username: String) async {
        await services.blockUser(username)
        forget(username)
    }

    func forget(_ username: String) {
        probes[username] = nil
        unflag(username)
    }

    func clearDetected() {
        detectedLeechers.removeAll()
        messagedLeechers.removeAll()
        shareCounts.removeAll()
        for (user, probe) in probes where probe == .leecher {
            probes[user] = nil
        }
        persist(Self.detectedKey, [])
        persist(Self.messagedKey, [])
    }

    // MARK: - Persistence

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if let loaded = try await services.loadSettings() {
                settings = loaded
            }
            detectedLeechers = Set(try await services.loadNames(Self.detectedKey) ?? [])
            messagedLeechers = Set(try await services.loadNames(Self.messagedKey) ?? [])
        } catch {
            logger.error("Failed to load leech state: \(error.localizedDescription)")
        }
    }

    private func saveSettings() async {
        do {
            try await services.saveSettings(settings)
        } catch {
            logger.error("Failed to save leech settings: \(error.localizedDescription)")
        }
    }

    private func persist(_ key: String, _ names: Set<String>) {
        let sorted = names.sorted()
        Task {
            do {
                try await services.saveNames(key, sorted)
            } catch {
                logger.error("Failed to persist \(key): \(error.localizedDescription)")
            }
        }
    }
}

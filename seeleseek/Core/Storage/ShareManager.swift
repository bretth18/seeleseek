import Foundation
import os

/// Manages shared folders and file index for the SoulSeek client
@Observable
@MainActor
final class ShareManager {
    private let logger = Logger(subsystem: "com.seeleseek", category: "ShareManager")

    // MARK: - State

    private(set) var sharedFolders: [SharedFolder] = []
    private(set) var fileIndex: [IndexedFile] = []
    private(set) var isScanning = false
    private(set) var scanProgress: Double = 0
    private(set) var lastScanDate: Date?

    // Computed stats
    var totalFiles: Int { fileIndex.count }
    var totalFolders: Int { sharedFolders.count }
    var totalSize: UInt64 { fileIndex.reduce(0) { $0 + $1.size } }

    // MARK: - Types

    struct SharedFolder: Identifiable, Codable, Hashable {
        let id: UUID
        let path: String
        var fileCount: Int
        var totalSize: UInt64
        var lastScanned: Date?

        init(id: UUID = UUID(), path: String, fileCount: Int = 0, totalSize: UInt64 = 0, lastScanned: Date? = nil) {
            self.id = id
            self.path = path
            self.fileCount = fileCount
            self.totalSize = totalSize
            self.lastScanned = lastScanned
        }

        var displayName: String {
            URL(fileURLWithPath: path).lastPathComponent
        }
    }

    struct IndexedFile: Identifiable, Sendable {
        let id: UUID
        let localPath: String      // Full local path
        let sharedPath: String     // SoulSeek-style path (backslash separated)
        let filename: String
        let size: UInt64
        let bitrate: UInt32?
        let duration: UInt32?
        let fileExtension: String

        init(localPath: String, sharedPath: String, size: UInt64, bitrate: UInt32? = nil, duration: UInt32? = nil) {
            self.id = UUID()
            self.localPath = localPath
            self.sharedPath = sharedPath
            self.filename = URL(fileURLWithPath: localPath).lastPathComponent
            self.size = size
            self.bitrate = bitrate
            self.duration = duration
            self.fileExtension = URL(fileURLWithPath: localPath).pathExtension.lowercased()
        }
    }

    // MARK: - Persistence Keys

    private let sharedFoldersKey = "SeeleSeek.SharedFolders"

    // MARK: - Initialization

    init() {
        load()
    }

    // MARK: - Folder Management

    func addFolder(_ url: URL) {
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to access security-scoped resource: \(url.path)")
            return
        }

        // Store bookmark for persistence
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: "bookmark-\(url.path)")
        } catch {
            logger.error("Failed to create bookmark: \(error.localizedDescription)")
        }

        let folder = SharedFolder(path: url.path)

        // Avoid duplicates
        guard !sharedFolders.contains(where: { $0.path == folder.path }) else {
            logger.info("Folder already shared: \(url.path)")
            return
        }

        sharedFolders.append(folder)
        save()

        // Scan the new folder
        Task {
            await scanFolder(folder)
        }
    }

    func removeFolder(_ folder: SharedFolder) {
        sharedFolders.removeAll { $0.id == folder.id }

        // Remove indexed files from this folder
        fileIndex.removeAll { $0.localPath.hasPrefix(folder.path) }

        // Stop accessing security-scoped resource
        URL(fileURLWithPath: folder.path).stopAccessingSecurityScopedResource()

        // Remove bookmark
        UserDefaults.standard.removeObject(forKey: "bookmark-\(folder.path)")

        save()
    }

    // MARK: - Scanning

    func rescanAll() async {
        guard !isScanning else { return }

        isScanning = true
        scanProgress = 0
        fileIndex.removeAll()

        for (index, folder) in sharedFolders.enumerated() {
            await scanFolder(folder)
            scanProgress = Double(index + 1) / Double(sharedFolders.count)
        }

        lastScanDate = Date()
        isScanning = false
        save()

        logger.info("Scan complete: \(self.totalFiles) files in \(self.totalFolders) folders")
    }

    private func scanFolder(_ folder: SharedFolder) async {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: folder.path)

        // Try to restore bookmark access
        if let bookmarkData = UserDefaults.standard.data(forKey: "bookmark-\(folder.path)") {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
            }
        }

        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("Failed to enumerate folder: \(folder.path)")
            return
        }

        var folderFileCount = 0
        var folderTotalSize: UInt64 = 0
        let basePath = folderURL.path

        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])

                guard resourceValues.isDirectory != true else { continue }

                let size = UInt64(resourceValues.fileSize ?? 0)
                let relativePath = String(fileURL.path.dropFirst(basePath.count))
                let sharedPath = folder.displayName + relativePath.replacingOccurrences(of: "/", with: "\\")

                // Extract audio metadata if it's an audio file
                let bitrate = extractBitrate(from: fileURL)

                let indexed = IndexedFile(
                    localPath: fileURL.path,
                    sharedPath: sharedPath,
                    size: size,
                    bitrate: bitrate
                )

                fileIndex.append(indexed)
                folderFileCount += 1
                folderTotalSize += size
            } catch {
                logger.debug("Failed to read file: \(fileURL.path)")
            }
        }

        // Update folder stats
        if let index = sharedFolders.firstIndex(where: { $0.id == folder.id }) {
            sharedFolders[index].fileCount = folderFileCount
            sharedFolders[index].totalSize = folderTotalSize
            sharedFolders[index].lastScanned = Date()
        }

        logger.info("Scanned \(folder.displayName): \(folderFileCount) files")
    }

    private func extractBitrate(from url: URL) -> UInt32? {
        // Simple bitrate extraction - in a real app, use AVFoundation
        let audioExtensions = ["mp3", "flac", "ogg", "m4a", "aac", "wav"]
        guard audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }

        // For now, estimate based on file size and typical song length (~4 min)
        // Real implementation would use AVAsset
        return nil
    }

    // MARK: - Search

    /// Search local files for a query (used when peers search us)
    func search(query: String) -> [IndexedFile] {
        let terms = query.lowercased().split(separator: " ").map(String.init)

        return fileIndex.filter { file in
            let searchable = file.sharedPath.lowercased()
            return terms.allSatisfy { searchable.contains($0) }
        }
    }

    /// Convert indexed files to SharedFile format for responses
    func toSharedFiles() -> [SharedFile] {
        // Group by folder
        var folders: [String: [IndexedFile]] = [:]

        for file in fileIndex {
            let components = file.sharedPath.split(separator: "\\")
            if components.count > 1 {
                let folderPath = components.dropLast().joined(separator: "\\")
                folders[folderPath, default: []].append(file)
            }
        }

        // Build folder tree
        return sharedFolders.map { folder in
            SharedFile(
                filename: folder.displayName,
                isDirectory: true,
                children: buildChildren(for: folder.displayName, from: folders)
            )
        }
    }

    private func buildChildren(for prefix: String, from folders: [String: [IndexedFile]]) -> [SharedFile] {
        var result: [SharedFile] = []

        // Find direct children (files and subfolders)
        let directFiles = fileIndex.filter { file in
            let components = file.sharedPath.split(separator: "\\")
            return components.count == 2 && file.sharedPath.hasPrefix(prefix)
        }

        for file in directFiles {
            result.append(SharedFile(
                filename: file.sharedPath,
                size: file.size,
                bitrate: file.bitrate,
                duration: file.duration
            ))
        }

        // Find subfolders
        let subfolders = Set(folders.keys.filter { $0.hasPrefix(prefix + "\\") }
            .compactMap { path -> String? in
                let remaining = path.dropFirst(prefix.count + 1)
                if let nextSeparator = remaining.firstIndex(of: "\\") {
                    return prefix + "\\" + remaining[..<nextSeparator]
                }
                return path
            })

        for subfolder in subfolders {
            result.append(SharedFile(
                filename: subfolder,
                isDirectory: true,
                children: buildChildren(for: subfolder, from: folders)
            ))
        }

        return result
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(sharedFolders)
            UserDefaults.standard.set(data, forKey: sharedFoldersKey)
        } catch {
            logger.error("Failed to save shared folders: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: sharedFoldersKey) else { return }

        do {
            sharedFolders = try JSONDecoder().decode([SharedFolder].self, from: data)

            // Restore bookmark access and rescan
            Task {
                await rescanAll()
            }
        } catch {
            logger.error("Failed to load shared folders: \(error.localizedDescription)")
        }
    }
}

import Foundation

nonisolated struct CrashReport: Sendable {
    let fileURL: URL
    let date: Date
    let fullText: String
    let appVersion: String
    let buildVersion: String
    let osVersion: String
    let binaryUUID: String?
    let exception: String?
    let termination: String?
    let applicationInfo: [String]
    let crashedThread: [String]

    static let crashBugType = "309"
    static let newIssueURL = URL(string: "https://github.com/bretth18/seeleseek/issues/new")!
    static let maxFrames = 30

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
    }

    /// Newest crash report for `processName` written after `since`.
    static func newest(in directory: URL, processName: String, since: Date) -> CrashReport? {
        let keys: [URLResourceKey] = [.creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
        ) else { return nil }

        let candidates = urls
            .filter { $0.pathExtension == "ips" && $0.lastPathComponent.hasPrefix("\(processName)-") }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: Set(keys)).creationDate,
                      date > since else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }

        return candidates.lazy.compactMap { url, date in
            (try? String(contentsOf: url, encoding: .utf8))
                .flatMap { parse($0, fileURL: url, date: date, processName: processName) }
        }.first
    }

    /// Hang and resource reports share the `.ips` extension; only bug type
    /// 309 is a crash.
    static func parse(_ text: String, fileURL: URL, date: Date, processName: String) -> CrashReport? {
        let parts = text.split(separator: "\n", maxSplits: 1)
        guard let header = json(parts.first),
              header["bug_type"] as? String == crashBugType,
              header["app_name"] as? String == processName
        else { return nil }
        let body = json(parts.count > 1 ? parts[1] : nil) ?? [:]

        let osVersion: String = {
            if let os = body["osVersion"] as? [String: Any], let train = os["train"] as? String {
                return [train, (os["build"] as? String).map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
            }
            return header["os_version"] as? String ?? "unknown"
        }()

        let exception = (body["exception"] as? [String: Any]).map { e in
            [e["type"] as? String, (e["signal"] as? String).map { "(\($0))" }, e["subtype"] as? String]
                .compactMap(\.self).joined(separator: " ")
        }
        let termination = (body["termination"] as? [String: Any]).flatMap { t in
            t["indicator"] as? String ?? t["namespace"] as? String
        }

        // `asi` carries the fatalError / precondition message, keyed by image.
        let applicationInfo = (body["asi"] as? [String: Any] ?? [:])
            .sorted { $0.key < $1.key }
            .flatMap { key, value in ((value as? [String]) ?? []).map { "\(key): \($0)" } }

        return CrashReport(
            fileURL: fileURL,
            date: date,
            fullText: text,
            appVersion: header["app_version"] as? String ?? "unknown",
            buildVersion: header["build_version"] as? String ?? "unknown",
            osVersion: osVersion,
            binaryUUID: header["slice_uuid"] as? String,
            exception: exception,
            termination: termination,
            applicationInfo: applicationInfo,
            crashedThread: crashedThreadFrames(body)
        )
    }

    /// Unsymbolicated frames keep image + offset so they can be resolved
    /// against the release's dSYM later.
    private static func crashedThreadFrames(_ body: [String: Any]) -> [String] {
        guard let threads = body["threads"] as? [[String: Any]] else { return [] }
        let index = body["faultingThread"] as? Int
        guard let thread = index.flatMap({ threads.indices.contains($0) ? threads[$0] : nil })
                ?? threads.first(where: { $0["triggered"] as? Bool == true }),
              let frames = thread["frames"] as? [[String: Any]]
        else { return [] }
        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "???" }

        return frames.prefix(maxFrames).enumerated().map { i, frame in
            let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil } ?? "???"
            let offset = (frame["imageOffset"] as? Int).map { "+ 0x\(String($0, radix: 16))" } ?? ""
            let symbol = (frame["symbol"] as? String).map { "  \($0)" } ?? ""
            let source = (frame["sourceFile"] as? String).map { file in
                (frame["sourceLine"] as? Int).map { "  (\(file):\($0))" } ?? ""
            } ?? ""
            return "\(i)".padding(toLength: 4, withPad: " ", startingAt: 0)
                + image.padding(toLength: 24, withPad: " ", startingAt: 0)
                + offset + symbol + source
        }
    }

    private static func json(_ line: Substring?) -> [String: Any]? {
        guard let line, let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    var issueTitle: String {
        "Crash in \(appVersion): \(exception ?? "unknown exception")"
    }

    var issueBody: String {
        var lines = [
            "**Version:** \(appVersion) (\(buildVersion))",
            "**macOS:** \(osVersion)",
            "**Exception:** \(exception ?? "unknown")",
            "**Termination:** \(termination ?? "unknown")",
        ]
        if let binaryUUID { lines.append("**Binary UUID:** `\(binaryUUID)`") }
        if !applicationInfo.isEmpty {
            lines += ["", "**Message:**", "```", applicationInfo.joined(separator: "\n"), "```"]
        }
        lines += [
            "",
            "**What were you doing when it crashed?**",
            "",
            "",
            "",
            "**Crashed thread:**",
            "```",
            crashedThread.isEmpty ? "(not available)" : crashedThread.joined(separator: "\n"),
            "```",
            "",
            "**Full report:**",
            "<!-- The full crash report is on your clipboard. Paste it below. -->",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    var issueURL: URL {
        var components = URLComponents(url: Self.newIssueURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "title", value: issueTitle),
            URLQueryItem(name: "body", value: issueBody),
        ]
        return components.url ?? Self.newIssueURL
    }
}

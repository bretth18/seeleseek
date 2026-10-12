import Foundation
import Testing
@testable import seeleseek

@Suite("Crash report")
@MainActor
struct CrashReportTests {
    static func ips(name: String = "seeleseek", bugType: String = "309", asi: Bool = false) -> String {
        let header = """
        {"app_name":"\(name)","timestamp":"2026-10-10 06:50:00.00 -0700","app_version":"1.8.0","slice_uuid":"7ebbe6c1-b9f3-3338-9ae4-0f0c7982c8f0","build_version":"42","bug_type":"\(bugType)","os_version":"macOS 15.8.1 (24G90)","name":"\(name)"}
        """
        let asiField = asi ? #""asi":{"libswiftCore.dylib":["Fatal error: Index out of range"]},"# : ""
        let body = """
        {\(asiField)"osVersion":{"train":"macOS 15.8.1","build":"24G90"},"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"termination":{"indicator":"Trace/BPT trap: 5","namespace":"SIGNAL"},"faultingThread":1,"threads":[{"frames":[{"imageIndex":1,"imageOffset":16}]},{"triggered":true,"frames":[{"imageIndex":0,"imageOffset":1064,"symbol":"SearchState.apply()","sourceFile":"SearchState.swift","sourceLine":12},{"imageIndex":0,"imageOffset":4096},{"imageIndex":9,"imageOffset":1}]}],"usedImages":[{"name":"seeleseek"},{"name":"AppKit"}]}
        """
        return header + "\n" + body
    }

    static let url = URL(fileURLWithPath: "/tmp/seeleseek-2026-10-10-065000.ips")

    @Test("Summary fields come from the header and body")
    func parsesSummary() throws {
        let report = try #require(CrashReport.parse(Self.ips(asi: true), fileURL: Self.url, date: .now, processName: "seeleseek"))
        #expect(report.appVersion == "1.8.0")
        #expect(report.buildVersion == "42")
        #expect(report.osVersion == "macOS 15.8.1 (24G90)")
        #expect(report.exception == "EXC_BREAKPOINT (SIGTRAP)")
        #expect(report.termination == "Trace/BPT trap: 5")
        #expect(report.applicationInfo == ["libswiftCore.dylib: Fatal error: Index out of range"])
    }

    @Test("Crashed thread frames keep image offsets and tolerate bad image indexes")
    func crashedThread() throws {
        let report = try #require(CrashReport.parse(Self.ips(), fileURL: Self.url, date: .now, processName: "seeleseek"))
        #expect(report.crashedThread.count == 3)
        #expect(report.crashedThread[0].contains("seeleseek"))
        #expect(report.crashedThread[0].contains("+ 0x428  SearchState.apply()  (SearchState.swift:12)"))
        #expect(report.crashedThread[1].hasSuffix("+ 0x1000"))
        #expect(report.crashedThread[2].contains("???"))
    }

    @Test("Hang reports and other processes are ignored")
    func filters() {
        #expect(CrashReport.parse(Self.ips(bugType: "298"), fileURL: Self.url, date: .now, processName: "seeleseek") == nil)
        #expect(CrashReport.parse(Self.ips(name: "other"), fileURL: Self.url, date: .now, processName: "seeleseek") == nil)
        #expect(CrashReport.parse("not json", fileURL: Self.url, date: .now, processName: "seeleseek") == nil)
    }

    @Test("Issue link carries title and body and stays under GitHub's URL limit")
    func issueURL() throws {
        let report = try #require(CrashReport.parse(Self.ips(asi: true), fileURL: Self.url, date: .now, processName: "seeleseek"))
        let components = try #require(URLComponents(url: report.issueURL, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["title"] == "Crash in 1.8.0: EXC_BREAKPOINT (SIGTRAP)")
        #expect(items["body"]??.contains("SearchState.apply()") == true)
        #expect(report.issueURL.absoluteString.count < 8000)
    }

    @Test("Launch check finds only reports newer than the last launch")
    func launchCheck() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = TestDefaults.isolated()

        let state = CrashReportState(defaults: defaults, directory: dir, processName: "seeleseek")
        await state.checkOnLaunch()
        #expect(state.pendingReport == nil)

        try Self.ips().write(to: dir.appending(path: "seeleseek-2026-10-10-065000.ips"), atomically: true, encoding: .utf8)
        try Self.ips(bugType: "298").write(to: dir.appending(path: "seeleseek-2026-10-10-070000.ips"), atomically: true, encoding: .utf8)

        await state.checkOnLaunch()
        #expect(state.showPrompt)
        #expect(state.pendingReport?.fileURL.lastPathComponent == "seeleseek-2026-10-10-065000.ips")

        let next = CrashReportState(defaults: defaults, directory: dir, processName: "seeleseek")
        await next.checkOnLaunch()
        #expect(next.pendingReport == nil)
    }

    @Test("Disabled prompt still advances the cutoff")
    func disabled() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = TestDefaults.isolated()
        try Self.ips().write(to: dir.appending(path: "seeleseek-2026-10-10-065000.ips"), atomically: true, encoding: .utf8)

        let state = CrashReportState(defaults: defaults, directory: dir, processName: "seeleseek")
        state.offerOnLaunch = false
        await state.checkOnLaunch()
        #expect(state.pendingReport == nil)

        state.offerOnLaunch = true
        await state.checkOnLaunch()
        #expect(state.pendingReport == nil)
    }
}

import Foundation
import Testing

/// Every `#Preview` in the app target must sit inside `#if DEBUG`. The
/// macro expansion is compiled into Release otherwise and measurably
/// grows the shipped binary. The build does not enforce this, so a
/// source scan does.
@Suite("Preview DEBUG guard")
struct PreviewDebugGuardTests {

    @Test("No #Preview outside #if DEBUG in the app target")
    func previewsAreDebugOnly() throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let appDir = testsDir.deletingLastPathComponent().appendingPathComponent("seeleseek")
        let enumerator = try #require(FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil))

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            var conditions: [String] = []
            for (number, raw) in source.components(separatedBy: "\n").enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#if ") {
                    conditions.append(line)
                } else if line.hasPrefix("#endif") {
                    _ = conditions.popLast()
                } else if line.hasPrefix("#Preview") {
                    let guarded = conditions.contains { $0.contains("DEBUG") }
                    if !guarded {
                        offenders.append("\(url.lastPathComponent):\(number + 1)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "Unguarded #Preview: \(offenders.joined(separator: ", "))")
    }
}

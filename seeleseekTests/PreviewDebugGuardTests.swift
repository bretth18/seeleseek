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
            // One entry per open `#if`: true while inside a branch that is
            // exactly `DEBUG`, false in any other branch of that block.
            var branches: [Bool] = []
            for (number, raw) in source.components(separatedBy: "\n").enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#if ") {
                    branches.append(line == "#if DEBUG")
                } else if line.hasPrefix("#elseif ") || line.hasPrefix("#else") {
                    if !branches.isEmpty { branches[branches.count - 1] = line == "#elseif DEBUG" }
                } else if line.hasPrefix("#endif") {
                    _ = branches.popLast()
                } else if line.hasPrefix("#Preview") {
                    if !branches.contains(true) {
                        offenders.append("\(url.lastPathComponent):\(number + 1)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "Unguarded #Preview: \(offenders.joined(separator: ", "))")
    }
}

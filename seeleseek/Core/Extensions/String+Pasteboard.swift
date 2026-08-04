import AppKit

extension String {
    /// Replaces the general pasteboard with this string. `clearContents()`
    /// is required first — without it the new string is added as an extra
    /// representation and the previous item can win on paste.
    func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(self, forType: .string)
    }
}

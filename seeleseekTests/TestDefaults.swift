import Foundation

/// Isolated `UserDefaults` for tests. The test host runs under the real
/// app bundle id, so `UserDefaults.standard` IS the user's live
/// preferences — a `ShareManager()` built on it wiped the user's real
/// `SeeleSeek.SharedFolders` on every suite run.
enum TestDefaults {
    static func isolated() -> UserDefaults {
        let name = "computerdata.seeleseek.tests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

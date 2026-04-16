import Foundation

// MARK: - Byte counts

public extension Int64 {
    var formattedBytes: String {
        guard self > 0 else { return "0 KB" }
        return formatted(.byteCount(style: .file))
    }
    var formattedSpeed: String { formattedBytes + "/s" }
}

public extension UInt32 {
    var formattedBytes: String { Int64(self).formattedBytes }
    var formattedSpeed: String { Int64(self).formattedSpeed }
}

public extension UInt64 {
    var formattedBytes: String { Int64(self).formattedBytes }
    var formattedSpeed: String { Int64(self).formattedSpeed }
}

public extension Int {
    var formattedBytes: String { Int64(self).formattedBytes }
    var formattedSpeed: String { Int64(self).formattedSpeed }
}

public extension Double {
    var formattedBytes: String { Int64(self).formattedBytes }
    var formattedSpeed: String { Int64(self).formattedSpeed }
}

// MARK: - Durations

public extension Duration {
    /// Compact "1h 30m" / "5m 30s" / "42s" style.
    var formattedCompact: String {
        let total = Int(components.seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

public extension TimeInterval {
    /// Compact duration (e.g., "5m 30s").
    var formattedDuration: String {
        Duration.seconds(Int(self)).formattedCompact
    }
}

public extension Date {
    /// Compact elapsed time since this date (e.g., "5m 30s").
    var durationSinceNow: String {
        Date().timeIntervalSince(self).formattedDuration
    }
}

public extension Int {
    /// Audio track duration as MM:SS.
    var formattedAudioDuration: String {
        Duration.seconds(self).formatted(.time(pattern: .minuteSecond))
    }
}

// MARK: - Country flags

public enum CountryFormatter {
    /// Two-letter country code → flag emoji.
    public static func flag(for countryCode: String) -> String {
        guard countryCode.count == 2 else { return "" }
        let base: UInt32 = 127397
        var flag = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            if let unicode = UnicodeScalar(base + scalar.value) {
                flag.append(Character(unicode))
            }
        }
        return flag
    }
}

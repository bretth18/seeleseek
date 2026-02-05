import Foundation

// MARK: - Byte Formatting

/// Centralized byte and speed formatting utilities
enum ByteFormatter {
    /// Formats byte count into human-readable string (KB, MB, GB, etc.)
    static func format(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
    }

    /// Formats bytes per second into human-readable speed string
    static func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
    }

    /// Formats UInt32 speed value (convenience overload)
    static func formatSpeed(_ bytesPerSecond: UInt32) -> String {
        formatSpeed(Int64(bytesPerSecond))
    }
}

// MARK: - Number Formatting

/// Centralized number formatting utilities
enum NumberFormatters {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    /// Formats a number with thousands separators
    static func format(_ value: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Formats a UInt32 with thousands separators
    static func format(_ value: UInt32) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Formats a UInt64 with thousands separators
    static func format(_ value: UInt64) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Date/Time Formatting

/// Centralized date and time formatting utilities
enum DateTimeFormatters {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Formats time only (e.g., "3:45 PM")
    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Formats date only (e.g., "Jan 15, 2024")
    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Formats both date and time (e.g., "1/15/24, 3:45 PM")
    static func formatDateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    /// Formats a relative time (e.g., "5 min ago")
    static func formatRelative(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Formats a duration in seconds (e.g., "5m 30s" or "2h 15m")
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    /// Formats duration since a given date
    static func formatDurationSince(_ date: Date) -> String {
        formatDuration(Date().timeIntervalSince(date))
    }

    /// Formats audio duration in MM:SS format
    static func formatAudioDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Country Code Utilities

/// Utilities for country codes and flag emoji
enum CountryFormatter {
    /// Converts a two-letter country code to its flag emoji
    static func flag(for countryCode: String) -> String {
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

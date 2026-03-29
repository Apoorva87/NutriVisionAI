import Foundation

/// Centralized timezone used for all date display, grouping, and queries.
/// Reads from UserDefaults; falls back to the device's current timezone.
enum AppTimeZone {
    private static let key = "app_timezone_identifier"

    /// The active timezone (user-selected or device default).
    static var current: TimeZone {
        if let id = UserDefaults.standard.string(forKey: key),
           let tz = TimeZone(identifier: id) {
            return tz
        }
        return .current
    }

    /// Whether the user has manually overridden the timezone.
    static var isManual: Bool {
        UserDefaults.standard.string(forKey: key) != nil
    }

    /// Set a manual timezone override. Pass `nil` to revert to auto (device).
    static func set(_ identifier: String?) {
        if let identifier {
            UserDefaults.standard.set(identifier, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Helpers

    /// Today's date string ("yyyy-MM-dd") in the app timezone.
    static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = current
        return fmt.string(from: Date())
    }

    /// Convert an ISO 8601 UTC timestamp to a local date string ("yyyy-MM-dd").
    static func localDateString(from isoString: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: isoString) else {
            // Fallback: try without fractional seconds
            let basic = ISO8601DateFormatter()
            guard let d = basic.date(from: isoString) else {
                return String(isoString.prefix(10))
            }
            return formatDate(d)
        }
        return formatDate(date)
    }

    /// Format a Date to "yyyy-MM-dd" in the app timezone.
    static func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = current
        return fmt.string(from: date)
    }

    /// Current hour (0-23) in the app timezone.
    static func currentHour() -> Int {
        var cal = Calendar.current
        cal.timeZone = current
        return cal.component(.hour, from: Date())
    }

    /// UTC offset string for SQLite queries (e.g., "+05:30" or "-07:00").
    static func sqliteOffsetModifier() -> String {
        let seconds = current.secondsFromGMT()
        let h = abs(seconds) / 3600
        let m = (abs(seconds) % 3600) / 60
        let sign = seconds >= 0 ? "+" : "-"
        return String(format: "%@%02d:%02d", sign, h, m)
    }
}

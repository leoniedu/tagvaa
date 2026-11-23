import Foundation

public struct GPSFix: Equatable {
    public var lat: Double
    public var lon: Double
    public var speedMS: Double?
    public var course: Double?
    public var hAccM: Double?
    public var utc: Date

    public init(lat: Double, lon: Double, speedMS: Double?, course: Double?, hAccM: Double?, utc: Date) {
        (self.lat, self.lon, self.speedMS, self.course, self.hAccM, self.utc) = (lat, lon, speedMS, course, hAccM, utc)
    }
}

/// One CSV line per row, in the Bluefruit export layout `Timestamp,Mode,Data`.
enum Rows {
    static let header = "Timestamp,Mode,Data\n"

    static func rx(_ text: String, at date: Date, tz: TimeZone) -> String {
        line(date, tz, "RX", text)
    }

    static func info(_ text: String, at date: Date, tz: TimeZone) -> String {
        line(date, tz, "INFO", text)
    }

    static func gps(_ fix: GPSFix, at date: Date, tz: TimeZone) -> String {
        func f(_ v: Double?, _ digits: Int) -> String {
            guard let v, v.isFinite else { return "NA" }
            return String(format: "%.\(digits)f", v)
        }
        let utc = utcFormatter.string(from: fix.utc)
        let text = "lat=\(f(fix.lat, 5)) lon=\(f(fix.lon, 5)) speed_ms=\(f(fix.speedMS, 2)) "
            + "course=\(f(fix.course, 1)) hacc_m=\(f(fix.hAccM, 1)) utc=\(utc)"
        return line(date, tz, "GPS", text)
    }

    private static func line(_ date: Date, _ tz: TimeZone, _ mode: String, _ data: String) -> String {
        "\(timeOfDay(date, tz)),\(mode),\"\(data.replacingOccurrences(of: "\"", with: "\"\""))\"\n"
    }

    static func timeOfDay(_ date: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private static let utcFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

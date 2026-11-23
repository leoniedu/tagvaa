import Foundation
import XCTest

let bahia = TimeZone(identifier: "America/Bahia")!

func localDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, ms: Int = 0, tz: TimeZone = bahia) -> Date {
    var c = DateComponents()
    (c.year, c.month, c.day, c.hour, c.minute, c.second) = (y, mo, d, h, mi, s)
    c.nanosecond = ms * 1_000_000
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: c)!
}

func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Minimal RFC 4180 parser: quoted fields may hold commas, newlines and doubled quotes.
func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var chars = Array(text)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if inQuotes {
            if c == "\"" {
                if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
            } else { field.append(c) }
        } else if c == "\"" { inQuotes = true }
        else if c == "," { row.append(field); field = "" }
        else if c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
        else { field.append(c) }
        i += 1
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    chars.removeAll()
    return rows
}

func contents(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

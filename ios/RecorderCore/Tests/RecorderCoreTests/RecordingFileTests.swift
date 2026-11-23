import Foundation
import XCTest
@testable import RecorderCore

final class RecordingFileTests: XCTestCase {
    func testFileNameReplacesSpaces() {
        let start = localDate(2026, 11, 25, 6, 12, 4)
        XCTAssertEqual(RecordingFile.fileName(tagName: "tagvaa honu_A", start: start, tz: bahia),
                       "tagvaa-honu_A_2026-11-25T06-12-04.csv")
    }

    func testHeaderThenRows() throws {
        let url = tempDir().appendingPathComponent("r.csv")
        let file = try RecordingFile(creating: url)
        let t = localDate(2026, 11, 25, 6, 12, 4, ms: 120)
        try file.write(Rows.rx("12,345,1,2,3\n13,\"x\"", at: t, tz: bahia))
        try file.write(Rows.info("link-lost", at: t, tz: bahia))
        let rows = parseCSV(contents(url))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["Timestamp", "Mode", "Data"])
        XCTAssertEqual(rows[1], ["06:12:04.120", "RX", "12,345,1,2,3\n13,\"x\""])
        XCTAssertEqual(rows[2], ["06:12:04.120", "INFO", "link-lost"])
        try file.close()
    }

    func testTimestampFormat() {
        let t = localDate(2026, 11, 25, 6, 12, 4, ms: 120)
        XCTAssertTrue(Rows.info("stop", at: t, tz: bahia).hasPrefix("06:12:04.120,INFO,"))
        XCTAssertTrue(Rows.info("stop", at: t, tz: bahia).hasSuffix("\n"))
    }

    func testGPSRow() {
        let t = localDate(2026, 11, 25, 6, 12, 4, ms: 120)
        let fix = GPSFix(lat: -12.973123, lon: -38.512341, speedMS: nil, course: 181, hAccM: 4,
                         utc: Date(timeIntervalSince1970: 1_795_597_924.12))
        let rows = parseCSV(Rows.gps(fix, at: t, tz: bahia))
        XCTAssertEqual(rows[0][1], "GPS")
        XCTAssertEqual(rows[0][2],
                       "lat=-12.97312 lon=-38.51234 speed_ms=NA course=181.0 hacc_m=4.0 utc=2026-11-25T09:12:04.120Z")
    }

    func testAppendingDoesNotRepeatHeader() throws {
        let url = tempDir().appendingPathComponent("r.csv")
        let t = localDate(2026, 11, 25, 6, 12, 4)
        let first = try RecordingFile(creating: url)
        try first.write(Rows.info("start", at: t, tz: bahia))
        try first.close()
        let again = try RecordingFile(appendingTo: url)
        try again.write(Rows.info("resumed", at: t, tz: bahia))
        try again.close()
        let rows = parseCSV(contents(url))
        XCTAssertEqual(rows.filter { $0.first == "Timestamp" }.count, 1)
        XCTAssertEqual(rows.map { $0.last }, ["Data", "start", "resumed"])
    }

    func testCreateInMissingDirectoryThrows() {
        let url = tempDir().appendingPathComponent("missing/r.csv")
        XCTAssertThrowsError(try RecordingFile(creating: url))
    }
}

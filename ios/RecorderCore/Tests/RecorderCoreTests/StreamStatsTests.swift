import XCTest
@testable import RecorderCore

final class StreamStatsTests: XCTestCase {
    func testCountsSamplesAcrossSplitPackets() {
        var s = StreamStats()
        s.ingest("10,1,0,0,1000\n11,1")
        s.ingest("1,0,0,1000\n12,21,0,0,1000\n")
        XCTAssertEqual(s.samples, 3)
        XCTAssertEqual(s.lostSamples, 0)
    }

    func testGapCountsLost() {
        var s = StreamStats()
        s.ingest("10,1,0,0,1000\n11,11,0,0,1000\n15,51,0,0,1000\n")
        XCTAssertEqual(s.lostSamples, 3)
    }

    func testRebootIsNotLoss() {
        var s = StreamStats()
        s.ingest("5000,1,0,0,1000\n5001,11,0,0,1000\n0,5,0,0,1000\n1,15,0,0,1000\n")
        XCTAssertEqual(s.lostSamples, 0)
        XCTAssertEqual(s.samples, 4)
    }

    func testBatteryAndId() {
        var s = StreamStats()
        s.ingest("# battery t_ms=1000 mv=3957\n")
        s.ingest("# id name=tagvaa honu_A addr=C5:B5:C4:D3:E2:F1\n")
        XCTAssertEqual(s.batteryMV, 3957)
        XCTAssertEqual(s.tagIdLine, "# id name=tagvaa honu_A addr=C5:B5:C4:D3:E2:F1")
    }

    func testGarbageLineIgnored() {
        var s = StreamStats()
        s.ingest("10,1,0,0,1000\n12,34,5,6\n11,11,0,0,1000\n")
        XCTAssertEqual(s.samples, 2)
        XCTAssertEqual(s.lostSamples, 0)
    }
}

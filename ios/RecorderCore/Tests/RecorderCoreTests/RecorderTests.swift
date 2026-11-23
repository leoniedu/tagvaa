import XCTest
@testable import RecorderCore

final class FakeLink: TagLink {
    weak var delegate: TagLinkDelegate?
    var connects: [UUID] = []
    var disconnects = 0
    func connect(peripheralID: UUID) { connects.append(peripheralID) }
    func disconnect() { disconnects += 1 }
}

final class RecorderTests: XCTestCase {
    let tag = TagInfo(name: "tagvaa honu_A", peripheralID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
    var clock = localDate(2026, 11, 25, 6, 12, 4)
    var link = FakeLink()
    var dir = tempDir()

    func makeRecorder() -> Recorder {
        Recorder(link: link, directory: dir, now: { [unowned self] in self.clock }, tz: bahia, appVersion: "1.0")
    }

    func rows(_ r: Recorder) -> [[String]] { parseCSV(contents(r.fileURL!)) }

    func send(_ r: Recorder, _ text: String) { r.linkReceived(Data(text.utf8)) }

    func testStartCreatesFileWithStartInfo() {
        let r = makeRecorder()
        r.start(tag: tag)
        XCTAssertEqual(r.state, .connecting)
        XCTAssertEqual(r.fileURL?.lastPathComponent, "tagvaa-honu_A_2026-11-25T06-12-04.csv")
        XCTAssertEqual(rows(r).last, ["06:12:04.000", "INFO",
            "start date=2026-11-25 tz=America/Bahia app=1.0 tag=tagvaa honu_A peripheral=11111111-2222-3333-4444-555555555555"])
        XCTAssertEqual(link.connects, [tag.peripheralID])
    }

    func testReceivedPacketsAreWrittenAndCounted() {
        let r = makeRecorder()
        r.start(tag: tag)
        r.linkConnected()
        XCTAssertEqual(r.state, .recording)
        send(r, "1,10,0,0,1000\n")
        send(r, "2,20,0,0,1000\n")
        XCTAssertEqual(rows(r).filter { $0[1] == "RX" }.map { $0[2] }, ["1,10,0,0,1000\n", "2,20,0,0,1000\n"])
        XCTAssertEqual(r.stats.samples, 2)
    }

    func testDropWritesLostAndReconnects() {
        let r = makeRecorder()
        r.start(tag: tag)
        r.linkConnected()
        let file = r.fileURL
        r.linkDropped()
        XCTAssertEqual(r.state, .reconnecting)
        XCTAssertEqual(rows(r).last?[2], "link-lost")
        XCTAssertEqual(link.connects.count, 2)
        r.linkConnected()
        XCTAssertEqual(r.state, .recording)
        XCTAssertEqual(rows(r).last?[2], "link-restored")
        XCTAssertEqual(r.fileURL, file)
    }

    func testGapAfterReconnectCountsLost() {
        let r = makeRecorder()
        r.start(tag: tag)
        r.linkConnected()
        send(r, "1,10,0,0,1000\n2,20,0,0,1000\n3,30,0,0,1000\n")
        r.linkDropped()
        r.linkConnected()
        send(r, "50,500,0,0,1000\n")
        XCTAssertEqual(r.stats.lostSamples, 46)
    }

    func testStopClosesAndDisconnects() {
        let r = makeRecorder()
        r.start(tag: tag)
        r.linkConnected()
        r.stop()
        XCTAssertEqual(rows(r).last?[2], "stop")
        XCTAssertEqual(link.disconnects, 1)
        XCTAssertEqual(r.state, .idle)
        XCTAssertNil(r.activeSession)
        r.linkDropped()   // the disconnect's own callback must not restart anything
        XCTAssertEqual(r.state, .idle)
        XCTAssertEqual(link.connects.count, 1)
    }

    func testGPSRowsOnlyWhileRecording() {
        let fix = GPSFix(lat: -12.97, lon: -38.51, speedMS: 3, course: 90, hAccM: 5, utc: clock)
        let r = makeRecorder()
        r.add(fix)
        XCTAssertNil(r.fileURL)
        r.start(tag: tag)
        r.linkConnected()
        r.add(fix)
        XCTAssertEqual(rows(r).filter { $0[1] == "GPS" }.count, 1)
    }

    func testResumeAppendsWithoutHeader() {
        var r: Recorder? = makeRecorder()
        r!.start(tag: tag)
        r!.linkConnected()
        send(r!, "1,10,0,0,1000\n")
        let session = r!.activeSession!
        r = nil   // the app was killed
        let again = makeRecorder()
        again.resume(tag: session.tag, fileURL: session.fileURL, startedAt: session.startedAt)
        XCTAssertEqual(again.state, .connecting)
        XCTAssertEqual(link.connects.last, tag.peripheralID)
        let all = rows(again)
        XCTAssertEqual(all.filter { $0.first == "Timestamp" }.count, 1)
        XCTAssertEqual(all.last?[2], "resumed")
        XCTAssertEqual(again.startedAt, session.startedAt)
    }

    func testUnwritableDirectoryFails() {
        let notADir = dir.appendingPathComponent("file")
        FileManager.default.createFile(atPath: notADir.path, contents: Data())
        dir = notADir
        let r = makeRecorder()
        r.start(tag: tag)
        guard case .failed = r.state else { return XCTFail("expected failed, got \(r.state)") }
        XCTAssertTrue(link.connects.isEmpty)
    }
}

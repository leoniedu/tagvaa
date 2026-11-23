import Foundation

/// What the Tag's stream says about itself: samples received and lost (gaps
/// in `seq`), battery and identity. Packets can split lines; only complete
/// lines count.
public struct StreamStats: Equatable {
    public private(set) var samples = 0
    public private(set) var lostSamples = 0
    public private(set) var batteryMV: Int?
    public private(set) var tagIdLine: String?

    private var partial = ""
    private var lastSeq: Int?

    public init() {}

    public mutating func ingest(_ packet: String) {
        var lines = (partial + packet).components(separatedBy: "\n")
        partial = lines.removeLast()
        for line in lines { take(line) }
    }

    private mutating func take(_ line: String) {
        if line.hasPrefix("# battery") {
            if let mv = line.range(of: "mv=").map({ Int(line[$0.upperBound...].prefix { $0.isNumber }) }) {
                batteryMV = mv ?? batteryMV
            }
            return
        }
        if line.hasPrefix("# id ") {
            tagIdLine = line
            return
        }
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 5, fields.allSatisfy({ Int($0) != nil }), let seq = Int(fields[0]) else { return }
        samples += 1
        if let last = lastSeq, seq > last {
            lostSamples += seq - last - 1
        }
        lastSeq = seq
    }
}

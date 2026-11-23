import Foundation

/// The Bluetooth link to one Tag. `connect` keeps trying until it succeeds
/// (CoreBluetooth pending connections never time out).
public protocol TagLink: AnyObject {
    var delegate: TagLinkDelegate? { get set }
    func connect(peripheralID: UUID)
    func disconnect()
}

public protocol TagLinkDelegate: AnyObject {
    func linkConnected()
    func linkReceived(_ data: Data)
    func linkDropped()
}

public struct TagInfo: Codable, Equatable {
    public let name: String
    public let peripheralID: UUID

    public init(name: String, peripheralID: UUID) {
        self.name = name
        self.peripheralID = peripheralID
    }
}

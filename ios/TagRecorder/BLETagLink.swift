import CoreBluetooth
import RecorderCore

/// CoreBluetooth side of `TagLink`: finds Tags by name, connects to one, and
/// subscribes to the Nordic UART TX characteristic that carries the stream.
/// Runs on the main queue; the restore identifier lets iOS relaunch the app
/// for Bluetooth events after it was killed in the background.
final class BLETagLink: NSObject, TagLink {
    weak var delegate: TagLinkDelegate?

    static let uartService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let uartTX = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private var central: CBCentralManager!
    private var target: UUID?
    private var peripheral: CBPeripheral?
    private var onFound: ((TagInfo, Int) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "tagvaa.recorder"])
    }

    func scan(_ found: @escaping (TagInfo, Int) -> Void) {
        onFound = found
        if central.state == .poweredOn { startScan() }
    }

    func stopScan() {
        onFound = nil
        if central.state == .poweredOn { central.stopScan() }
    }

    func connect(peripheralID: UUID) {
        target = peripheralID
        if central.state == .poweredOn { connectTarget() }
    }

    func disconnect() {
        target = nil
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
    }

    private func startScan() {
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func connectTarget() {
        guard let target else { return }
        let p = peripheral?.identifier == target
            ? peripheral
            : central.retrievePeripherals(withIdentifiers: [target]).first
        guard let p else { return }
        peripheral = p
        p.delegate = self
        if p.state != .connected && p.state != .connecting { central.connect(p) }
    }
}

extension BLETagLink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if onFound != nil { startScan() }
            if let p = peripheral, p.state == .connected {
                p.discoverServices([Self.uartService])
            } else {
                connectTarget()
            }
        } else if central.state == .poweredOff, target != nil {
            delegate?.linkDropped()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        if let p = restored.first {
            peripheral = p
            p.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.hasPrefix("tagvaa") else { return }
        onFound?(TagInfo(name: name, peripheralID: peripheral.identifier), RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.uartService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if target != nil { delegate?.linkDropped() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if target != nil { delegate?.linkDropped() }
    }
}

extension BLETagLink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.uartService }) else { return }
        peripheral.discoverCharacteristics([Self.uartTX], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let tx = service.characteristics?.first(where: { $0.uuid == Self.uartTX }) else { return }
        peripheral.setNotifyValue(true, for: tx)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if characteristic.isNotifying { delegate?.linkConnected() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value { delegate?.linkReceived(data) }
    }
}

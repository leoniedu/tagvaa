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
    /// Services in the Tags' main advert: cadence (m3/m5) and UART (m4).
    static let advertised = [CBUUID(string: "1816"), uartService]

    private var central: CBCentralManager!
    private var target: UUID?
    private var peripheral: CBPeripheral?
    private var onFound: ((TagInfo, Int) -> Void)?
    /// Scanning to find `target` because iOS no longer knows it (new install,
    /// Bluetooth reset): `retrievePeripherals` comes back empty.
    private var seeking = false
    /// Connected but not subscribed after this long: drop and retry.
    private var watchdog: DispatchWorkItem?

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
        if central.state == .poweredOn && !seeking { central.stopScan() }
    }

    func connect(peripheralID: UUID) {
        target = peripheralID
        if central.state == .poweredOn { connectTarget() }
    }

    func disconnect() {
        target = nil
        watchdog?.cancel()
        endSeeking()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil
    }

    /// The picker scans for everything (foreground). Seeking alone filters by
    /// service, because iOS only delivers filtered scans in the background.
    private func startScan() {
        if onFound != nil {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else {
            central.scanForPeripherals(withServices: Self.advertised, options: nil)
        }
    }

    private func connectTarget() {
        guard let target else { return }
        let p = peripheral?.identifier == target
            ? peripheral
            : central.retrievePeripherals(withIdentifiers: [target]).first
        guard let p else {
            seeking = true
            startScan()
            return
        }
        peripheral = p
        p.delegate = self
        if p.state != .connected && p.state != .connecting { central.connect(p) }
    }

    private func endSeeking() {
        guard seeking else { return }
        seeking = false
        if onFound == nil && central.state == .poweredOn { central.stopScan() }
    }

    /// Any failure between connecting and subscribing: cancel the connection,
    /// so the disconnect callback makes the recorder try again.
    private func abandon(_ p: CBPeripheral) {
        watchdog?.cancel()
        central.cancelPeripheralConnection(p)
    }
}

extension BLETagLink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if onFound != nil || seeking { startScan() }
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
        if seeking, peripheral.identifier == target {
            endSeeking()
            connectTo(peripheral)
        }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.hasPrefix("tagvaa") else { return }
        onFound?(TagInfo(name: name, peripheralID: peripheral.identifier), RSSI.intValue)
    }

    private func connectTo(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        central.connect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        watchdog?.cancel()
        let check = DispatchWorkItem { [weak self] in self?.abandon(peripheral) }
        watchdog = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: check)
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
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.uartService }) else {
            return abandon(peripheral)
        }
        peripheral.discoverCharacteristics([Self.uartTX], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let tx = service.characteristics?.first(where: { $0.uuid == Self.uartTX }) else {
            return abandon(peripheral)
        }
        peripheral.setNotifyValue(true, for: tx)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, characteristic.isNotifying else { return abandon(peripheral) }
        watchdog?.cancel()
        delegate?.linkConnected()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value { delegate?.linkReceived(data) }
    }
}

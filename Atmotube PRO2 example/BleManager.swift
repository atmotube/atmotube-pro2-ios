import Foundation
import CoreBluetooth
import Combine
import iOSMcuManagerLibrary

class BleManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    static let ATMOTUBE_DATA_SERVICE_UUID = CBUUID(string: "BDA3C091-E5E0-4DAC-8170-7FCEF187A1D0")
    static let ATMOTUBE_DATA_CHAR_UUID = CBUUID(string: "BDA3C092-E5E0-4DAC-8170-7FCEF187A1D0")
    static let ATMOTUBE_PM_CHAR_UUID = CBUUID(string: "BDA3C093-E5E0-4DAC-8170-7FCEF187A1D0")
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var latestReading: AtmotubeReading?
    @Published var pmReading: (Double, Double, Double)?
    @Published var commandLogs: [String] = []
    @Published var discoveredDevices: [CBPeripheral] = []
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    private var pmCharacteristic: CBCharacteristic?
    
    var transport: McuMgrBleTransport?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private var isScanning = false

    func startScanning() {
        isScanning = true
        if centralManager.state == .poweredOn {
            discoveredDevices.removeAll()
            centralManager.scanForPeripherals(withServices: [BleManager.ATMOTUBE_DATA_SERVICE_UUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }
    
    func connect(to device: CBPeripheral) {
        stopScanning()
        peripheral = device
        peripheral?.delegate = self
        connectionState = .connecting
        centralManager.connect(device, options: nil)
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if isScanning {
                startScanning()
            }
        } else {
            connectionState = .disconnected
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        peripheral.discoverServices([BleManager.ATMOTUBE_DATA_SERVICE_UUID])
        
        // Initialize McuMgr Transport
        transport = McuMgrBleTransport(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        logCommand("Failed to connect: \(error?.localizedDescription ?? "Unknown")")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        self.peripheral = nil
        transport = nil
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == BleManager.ATMOTUBE_DATA_SERVICE_UUID {
                peripheral.discoverCharacteristics([BleManager.ATMOTUBE_DATA_CHAR_UUID, BleManager.ATMOTUBE_PM_CHAR_UUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == BleManager.ATMOTUBE_DATA_CHAR_UUID {
                dataCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == BleManager.ATMOTUBE_PM_CHAR_UUID {
                pmCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        connectionState = .ready
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == BleManager.ATMOTUBE_DATA_CHAR_UUID {
            let reading = AtmotubeReading.fromBytes(data: data, deviceMac: peripheral.identifier.uuidString)
            DispatchQueue.main.async {
                self.latestReading = reading
            }
        } else if characteristic.uuid == BleManager.ATMOTUBE_PM_CHAR_UUID {
            let pm = AtmotubeReading.parsePm(data: data)
            DispatchQueue.main.async {
                self.pmReading = pm
            }
        }
    }
    
    func logCommand(_ msg: String) {
        DispatchQueue.main.async {
            self.commandLogs.insert(msg, at: 0)
            if self.commandLogs.count > 50 {
                self.commandLogs.removeLast()
            }
        }
    }
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case ready
    case disconnecting
}

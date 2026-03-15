// BLEDebugScanner.swift
// Temporary debug scanner that finds ALL BLE peripherals and logs them.
// This helps us identify how the G2 glasses appear to CoreBluetooth.

import Foundation
import CoreBluetooth
import os.log

private let log = Logger(subsystem: "ai.xgx.evenclaw", category: "BLEDebug")

class BLEDebugScanner: NSObject, CBCentralManagerDelegate, ObservableObject {
    private var centralManager: CBCentralManager!
    @Published var discoveredDevices: [(name: String, uuid: String, rssi: Int)] = []
    @Published var connectedDevices: [(name: String, uuid: String)] = []
    @Published var bleState: String = "Initializing..."
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bleState = "Bluetooth ON — scanning..."
            log.info("BLE powered on — starting debug scan")
            
            // First: check ALL connected peripherals across common services
            let services: [CBUUID] = [
                CBUUID(string: "00002760-08c2-11e1-9073-0e8ac72e0000"), // G2 custom
                CBUUID(string: "180A"), // Device Info
                CBUUID(string: "180F"), // Battery
                CBUUID(string: "1800"), // Generic Access
                CBUUID(string: "1801"), // Generic Attribute
                CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), // Nordic UART
            ]
            
            for svc in services {
                let connected = central.retrieveConnectedPeripherals(withServices: [svc])
                for p in connected {
                    let name = p.name ?? "(no name)"
                    let entry = (name: name, uuid: p.identifier.uuidString)
                    log.info("CONNECTED via \(svc.uuidString): '\(name)' [\(p.identifier.uuidString)]")
                    if !connectedDevices.contains(where: { $0.uuid == entry.uuid }) {
                        connectedDevices.append(entry)
                    }
                }
            }
            
            // Then: scan for ALL advertising peripherals
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
            
            // Stop scan after 10s
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                central.stopScan()
                self?.bleState = "Scan complete — \(self?.discoveredDevices.count ?? 0) found, \(self?.connectedDevices.count ?? 0) connected"
                log.info("Debug scan complete")
            }
            
        case .poweredOff:
            bleState = "Bluetooth OFF"
        case .unauthorized:
            bleState = "Bluetooth UNAUTHORIZED"
        case .unsupported:
            bleState = "BLE not supported"
        default:
            bleState = "BLE state: \(central.state.rawValue)"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "(no name)"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString } ?? []
        
        log.info("ADVERTISING: '\(name)' RSSI=\(RSSI) services=\(services) uuid=\(peripheral.identifier.uuidString)")
        
        let entry = (name: name, uuid: peripheral.identifier.uuidString, rssi: RSSI.intValue)
        if !discoveredDevices.contains(where: { $0.uuid == entry.uuid }) {
            DispatchQueue.main.async {
                self.discoveredDevices.append(entry)
            }
        }
    }
}

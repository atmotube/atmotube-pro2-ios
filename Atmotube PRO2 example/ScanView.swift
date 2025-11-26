import SwiftUI
import CoreBluetooth

struct ScanView: View {
    @ObservedObject var bleManager: BleManager
    
    var body: some View {
        List(bleManager.discoveredDevices, id: \.identifier) { device in
            Button(action: {
                bleManager.connect(to: device)
            }) {
                HStack {
                    Text(device.name ?? "Unknown Device")
                    Spacer()
                    Text(device.identifier.uuidString)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
            }
        }
        .navigationTitle("Scan Atmotube PRO 2")
        .onAppear {
            bleManager.startScanning()
        }
        .onDisappear {
            bleManager.stopScanning()
        }
    }
}

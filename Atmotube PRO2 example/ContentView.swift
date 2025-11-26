import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BleManager()
    
    var body: some View {
        NavigationView {
            switch bleManager.connectionState {
            case .ready:
                DeviceView(bleManager: bleManager)
            case .connecting, .connected:
                VStack {
                    ProgressView("Connecting...")
                    Button("Cancel") {
                        bleManager.disconnect()
                    }
                    .padding(.top)
                }
            case .disconnected, .disconnecting:
                ScanView(bleManager: bleManager)
            }
        }
    }
}

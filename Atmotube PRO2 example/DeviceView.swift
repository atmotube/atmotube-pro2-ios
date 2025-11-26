import SwiftUI

struct DeviceView: View {
    @ObservedObject var bleManager: BleManager
    @State private var isDownloading = false
    @State private var downloadMessage = ""
    @State private var shareItem: ShareItem?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let reading = bleManager.latestReading {
                    let vocIndex = AtmotubeReading.formatSensorValue(reading.vocIndex as NSNumber)
                    let vocPpb = AtmotubeReading.formatSensorValue(reading.vocPpb as NSNumber)
                    SensorCard(title: "VOC", value: "\(vocIndex) / \(vocPpb) ppb")
                    
                    let temp = AtmotubeReading.formatSensorValue(reading.temperature as NSNumber, type: "temp")
                    SensorCard(title: "Temperature", value: temp + (Double(temp) != nil ? " °C" : ""))
                    
                    let hum = AtmotubeReading.formatSensorValue(reading.humidity as NSNumber, type: "hum")
                    SensorCard(title: "Humidity", value: hum + (Double(hum) != nil ? " %" : ""))
                    
                    let press = AtmotubeReading.formatSensorValue(reading.pressure as NSNumber, type: "press")
                    SensorCard(title: "Pressure", value: press + (Double(press) != nil ? " hPa" : ""))
                    
                    let co2 = AtmotubeReading.formatSensorValue(reading.co2Ppm as NSNumber)
                    SensorCard(title: "CO2", value: co2 + (Double(co2) != nil ? " ppm" : ""))

                    if let pm = bleManager.pmReading {
                        let pm1 = AtmotubeReading.formatSensorValue(pm.0 as NSNumber)
                        SensorCard(title: "PM 1.0", value: pm1 + (Double(pm1) != nil ? " µg/m³" : ""))
                        
                        let pm25 = AtmotubeReading.formatSensorValue(pm.1 as NSNumber)
                        SensorCard(title: "PM 2.5", value: pm25 + (Double(pm25) != nil ? " µg/m³" : ""))
                        
                        let pm10 = AtmotubeReading.formatSensorValue(pm.2 as NSNumber)
                        SensorCard(title: "PM 10", value: pm10 + (Double(pm10) != nil ? " µg/m³" : ""))
                    }
                } else {
                    Text("Waiting for data...")
                }
                
                Button(action: downloadHistory) {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Text("Download History")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .disabled(isDownloading)
                
                if !downloadMessage.isEmpty {
                    Text(downloadMessage)
                        .font(.caption)
                }
                
                Divider()
                
                // Shell Commands
                VStack(alignment: .leading, spacing: 10) {
                    Text("Shell Commands")
                        .font(.headline)
                    
                    HStack {
                        Button("Get FW Version") {
                            sendShellCommand("version app")
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Get PM Mode") {
                            sendShellCommand("pm status")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(commandLogs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                    .frame(height: 100)
                    .background(Color(.systemGray6))
                    .cornerRadius(5)
                }
                
                Button("Disconnect") {
                    bleManager.disconnect()
                }
                .foregroundColor(.red)
            }
            .padding()
        }
        .navigationTitle("Atmotube PRO 2")
        .sheet(item: $shareItem, onDismiss: {
            isDownloading = false
        }) { item in
            ActivityViewController(activityItems: [item.url])
        }
    }
    
    @State private var commandLogs: [String] = []
    
    private func sendShellCommand(_ command: String) {
        guard let transport = bleManager.transport else { return }
        let manager = ShellCommandManager(transport: transport)
        
        commandLogs.append("> \(command)")
        
        Task {
            let response = await manager.sendCommand(command)
            commandLogs.append(response)
        }
    }
    
    private func downloadHistory() {
        isDownloading = true
        downloadMessage = "Downloading..."
        
        Task {
            guard let transport = bleManager.transport else {
                downloadMessage = "Device not connected"
                isDownloading = false
                return
            }
            
            let historyManager = HistoryManager(transport: transport)
            if let fileURL = await historyManager.downloadHistory() {
                downloadMessage = "Saved to \(fileURL.lastPathComponent)"
                shareItem = ShareItem(url: fileURL)
                // isDownloading remains true until sheet is dismissed
            } else {
                downloadMessage = "Download failed or no new data"
                isDownloading = false
            }
        }
    }
}

struct SensorCard: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.body)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}

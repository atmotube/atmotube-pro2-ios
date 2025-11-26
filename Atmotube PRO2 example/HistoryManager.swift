import Foundation
import iOSMcuManagerLibrary

class HistoryManager {
    private let transport: McuMgrBleTransport
        
    init(transport: McuMgrBleTransport) {
        self.transport = transport
    }
    
    func downloadHistory() async -> URL? {
        let fsManager = FileSystemManager(transport: transport)
        
        // 1. Get list of files
        let fileList = await listFiles()
        if fileList.isEmpty { return nil }
        
        var allMeasurements: [HistoryMeasurement] = []
        
        // 2. Download each file
        for fileName in fileList {
            do {
                let fileURL = try await downloadFile(fsManager: fsManager, remotePath: fileName)
                // 3. Parse file
                let data = try Data(contentsOf: fileURL)
                let measurements = HistoryParser.parseStream(data: data)
                allMeasurements.append(contentsOf: measurements)
                
                try FileManager.default.removeItem(at: fileURL) // Clean up temp file
            } catch {
                print("Failed to download/parse \(fileName): \(error)")
            }
        }
        
        // 5. Export to CSV
        if !allMeasurements.isEmpty {
            return exportToCsv(measurements: allMeasurements)
        }
        return nil
    }
    
    private func listFiles() async -> [String] {
        let shellCommandManager = ShellCommandManager(transport: transport)
        let output = await shellCommandManager.sendCommand("history get")
        
        let clean = output.replacingOccurrences(of: "history get ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let files = clean.components(separatedBy: ";")
             .map { $0.components(separatedBy: ",")[0] }
             .filter { !$0.isEmpty && $0.contains("h_active") }
        return files
    }
    
    private var currentDownloadDelegate: HistoryDownloadDelegate?

    private func downloadFile(fsManager: FileSystemManager, remotePath: String) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("temp_history.bin")
            let delegate = HistoryDownloadDelegate(continuation: continuation, tempFile: tempFile)
            self.currentDownloadDelegate = delegate // Retain the delegate
            
            // Note: The actual method signature might vary slightly by version.
            // Based on common usage: download(name:delegate:)
            fsManager.download(name: remotePath, delegate: delegate)
        }
    }
}

// Delegate class for file download
class HistoryDownloadDelegate: FileDownloadDelegate {
    func downloadDidFail(with error: Error) {
        continuation.resume(throwing: error)
    }
    
    func downloadDidCancel() {
        continuation.resume(throwing: NSError(domain: "HistoryDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download canceled"]))
    }
    
    let continuation: CheckedContinuation<URL, Error>
    let tempFile: URL
    
    init(continuation: CheckedContinuation<URL, Error>, tempFile: URL) {
        self.continuation = continuation
        self.tempFile = tempFile
    }
    
    func download(of name: String, didFinish data: Data) {
        do {
            try data.write(to: tempFile)
            continuation.resume(returning: tempFile)
        } catch {
            continuation.resume(throwing: error)
        }
    }
    
    func download(of name: String, didFail error: Error) {
        continuation.resume(throwing: error)
    }
    
    func downloadProgressDidChange(bytesDownloaded: Int, fileSize: Int, timestamp: Date) {
        // Optional: report progress
    }
}
    
    private func exportToCsv(measurements: [HistoryMeasurement]) -> URL? {
        let fileName = "atmotube_history_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        var csvString = "Timestamp,Date,Temperature,Humidity,Pressure,Battery,Status,Flags,VOC Index,VOC ppb,NOx Index,CO2 ppm,PM1,PM2.5,PM10,Lat,Lon,PM0.5 (#),PM1 (#),PM2.5 (#),PM10 (#),Typical Particle (µm),Alt,Sat Fixed,Sat View,Accuracy\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US")
        
        for m in measurements {
            let date = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(m.timestamp)))
            let flagsStr = m.flags.joined(separator: "|")
            
            let vocIndexStr = AtmotubeReading.formatSensorValue(m.vocIndex as NSNumber?)
            let vocPpbStr = AtmotubeReading.formatSensorValue(m.vocPpb as NSNumber?)
            let noxIndexStr = AtmotubeReading.formatSensorValue(m.noxIndex as NSNumber?)
            let co2PpmStr = AtmotubeReading.formatSensorValue(m.co2Ppm as NSNumber?)
            
            let tempStr = AtmotubeReading.formatSensorValue(m.temperature as NSNumber?, type: "temp")
            let humStr = AtmotubeReading.formatSensorValue(m.humidity as NSNumber?, type: "hum")
            let pressStr = AtmotubeReading.formatSensorValue(m.pressure as NSNumber?, type: "press")
            
            let fmt: (Any?) -> String = { $0.map { "\($0)" } ?? "" }
            
            let line = "\(m.timestamp),\(date),\(tempStr),\(humStr),\(pressStr),\(fmt(m.batteryLevel)),\(fmt(m.statusFlags)),\(flagsStr),\(vocIndexStr),\(vocPpbStr),\(noxIndexStr),\(co2PpmStr),\(fmt(m.pm1)),\(fmt(m.pm25)),\(fmt(m.pm10)),\(fmt(m.latitude)),\(fmt(m.longitude)),\(fmt(m.pm05Particles)),\(fmt(m.pm1Particles)),\(fmt(m.pm25Particles)),\(fmt(m.pm10Particles)),\(fmt(m.typicalParticleSize)),\(fmt(m.altitude)),\(fmt(m.satellitesFixed)),\(fmt(m.satellitesView)),\(fmt(m.accuracy))\n"
            csvString.append(line)
        }
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to write CSV: \(error)")
            return nil
        }
    }

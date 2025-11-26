import Foundation

struct AtmotubeReading {
    let deviceMac: String
    let timestamp: Date
    let temperature: Double
    let humidity: Int
    let pressure: Double
    let vocIndex: Int
    let vocPpb: Int
    let noxIndex: Int
    let co2Ppm: Int
    let pm1: Double
    let pm25: Double
    let pm10: Double
    let batteryLevel: Int
    
    static let offValues: Set<Double> = [0xFFFF, 0xFFFF / 10.0, 0x7FFF]
    static let heatingValues: Set<Double> = [0xFFFE, 0xFFFE / 10.0, 0x7FFE]
    static let tInvalidValues: Set<Double> = [0x7FFF / 100.0, 0x7FFE / 100.0]
    static let hInvalidValues: Set<Double> = [-1.0]
    static let pInvalidValues: Set<Double> = [0xFFFFFFFF / 10.0]
    
    private static let PM_ENCODING_FLAG = 0x8000
    private static let PM_ENCODING_VALUE_MASK = 0x7FFF
    
    static func decodePmValue(raw: Int) -> Double {
        if (raw & PM_ENCODING_FLAG) != 0 {
            // Bit 15 set → integer format
            return Double(raw & PM_ENCODING_VALUE_MASK)
        } else {
            // Bit 15 clear → 0.1-precision format
            return Double(raw) / 10.0
        }
    }
    
    static func formatSensorValue(_ value: NSNumber?, type: String = "generic") -> String {
        guard let value = value else { return "" }
        let v = value.doubleValue
        
        if offValues.contains(v) { return "Off" }
        if heatingValues.contains(v) { return "Heating" }
        
        if type == "temp" && tInvalidValues.contains(v) { return "Off" }
        if type == "hum" && hInvalidValues.contains(v) { return "Off" }
        if type == "press" && pInvalidValues.contains(v) { return "Off" }
        
        return value.stringValue
    }
    
    static func fromBytes(data: Data, deviceMac: String) -> AtmotubeReading {
        let bytes = [UInt8](data)
        
        let temperatureRaw = (Int(bytes[1]) & 0xFF) << 8 | (Int(bytes[0]) & 0xFF)
        let temperature: Double = (temperatureRaw == 0xFFFF) ? 65535.0 : Double(Int16(bitPattern: UInt16(temperatureRaw))) / 100.0
        
        let humidityRaw = Int(bytes[2]) & 0xFF
        let humidity = (humidityRaw == 0xFF) ? -1 : humidityRaw
        
        let pressureRaw = (Int64(bytes[6]) & 0xFF) << 24 |
                          (Int64(bytes[5]) & 0xFF) << 16 |
                          (Int64(bytes[4]) & 0xFF) << 8 |
                          (Int64(bytes[3]) & 0xFF)
        let pressure = Double(pressureRaw) / 10.0
        
        func readUShort(offset: Int) -> Int {
            return (Int(bytes[offset + 1]) & 0xFF) << 8 | (Int(bytes[offset]) & 0xFF)
        }
        
        let vocIndex = readUShort(offset: 7)
        let vocPpb = readUShort(offset: 9)
        let noxIndex = readUShort(offset: 11)
        let co2Ppm = readUShort(offset: 13)
        let batteryLevel = Int(bytes[15]) & 0xFF
        
        return AtmotubeReading(
            deviceMac: deviceMac,
            timestamp: Date(),
            temperature: temperature,
            humidity: humidity,
            pressure: pressure,
            vocIndex: vocIndex,
            vocPpb: vocPpb,
            noxIndex: noxIndex,
            co2Ppm: co2Ppm,
            pm1: 0.0,
            pm25: 0.0,
            pm10: 0.0,
            batteryLevel: batteryLevel
        )
    }
    
    static func parsePm(data: Data) -> (Double, Double, Double) {
        let bytes = [UInt8](data)
        if bytes.count < 6 { return (0.0, 0.0, 0.0) }
        
        let pm1 = decodePmValue(raw: (Int(bytes[1]) & 0xFF) << 8 | (Int(bytes[0]) & 0xFF))
        let pm25 = decodePmValue(raw: (Int(bytes[3]) & 0xFF) << 8 | (Int(bytes[2]) & 0xFF))
        let pm10 = decodePmValue(raw: (Int(bytes[5]) & 0xFF) << 8 | (Int(bytes[4]) & 0xFF))
        
        return (pm1, pm25, pm10)
    }
}

struct HistoryMeasurement {
    let timestamp: Int64
    let temperature: Double?
    let humidity: Int?
    let pressure: Double?
    let batteryLevel: Int?
    let statusFlags: Int?
    let vocIndex: Int?
    let vocPpb: Int?
    let noxIndex: Int?
    let co2Ppm: Int?
    let pm1: Double?
    let pm25: Double?
    let pm10: Double?
    let latitude: Double?
    let longitude: Double?
    let pm05Particles: Int?
    let pm1Particles: Int?
    let pm25Particles: Int?
    let pm10Particles: Int?
    let typicalParticleSize: Double?
    let altitude: Double?
    let satellitesFixed: Int?
    let satellitesView: Int?
    let accuracy: Double?
    let flags: [String]
}

class HistoryParser {
    private static let VOC_BIT = 0b00000001
    private static let CO2_BIT = 0b00000010
    private static let PM_BIT = 0b00000100
    private static let PM_EXT_BIT = 0b00001000
    private static let GPS_BIT = 0b00010000
    private static let GPS_EXT_BIT = 0b00100000
    
    static func parseStream(data: Data) -> [HistoryMeasurement] {
        var list = [HistoryMeasurement]()
        let reader = CrcReader(data: data)
        
        while true {
            guard let historyType = reader.readU8(),
                  let packetType = reader.readU8() else { break }
            
            guard let tsSeconds = reader.readLeU32(),
                  let tempRaw = reader.readLeI16(),
                  let humidityU8 = reader.readU8(),
                  let pressure10 = reader.readLeU32(),
                  let batteryU8 = reader.readU8(),
                  let status = reader.readLeU16() else { break }
            
            let temp: Double = (tempRaw == -1) ? 65535.0 : Double(tempRaw) / 100.0 // Check if -1 is correct for 0xFFFF short
            // In Kotlin 0xFFFF.toShort() is -1.
            
            let hum = (humidityU8 == 0xFF) ? -1 : Int(humidityU8)
            let pressure = Double(pressure10) / 10.0
            
            var vocIndex: Int? = nil
            var vocPpb: Int? = nil
            var noxIndex: Int? = nil
            if (packetType & VOC_BIT) != 0 {
                vocIndex = reader.readLeU16()
                vocPpb = reader.readLeU16()
                noxIndex = reader.readLeU16()
            }
            
            var co2Ppm: Int? = nil
            if (packetType & CO2_BIT) != 0 {
                co2Ppm = reader.readLeU16()
            }
            
            var pm1: Double? = nil
            var pm25: Double? = nil
            var pm10: Double? = nil
            if (packetType & PM_BIT) != 0 {
                pm1 = AtmotubeReading.decodePmValue(raw: reader.readLeU16() ?? 0)
                pm25 = AtmotubeReading.decodePmValue(raw: reader.readLeU16() ?? 0)
                pm10 = AtmotubeReading.decodePmValue(raw: reader.readLeU16() ?? 0)
            }
            
            var latitude: Double? = nil
            var longitude: Double? = nil
            if (packetType & GPS_BIT) != 0 {
                if let latRaw = reader.readLeI32(), let lonRaw = reader.readLeI32() {
                    latitude = Double(latRaw) / 1000000.0
                    longitude = Double(lonRaw) / 1000000.0
                }
            }
            
            var pm05Particles: Int? = nil
            var pm1Particles: Int? = nil
            var pm25Particles: Int? = nil
            var pm10Particles: Int? = nil
            var typicalParticleSize: Double? = nil
            if (packetType & PM_EXT_BIT) != 0 {
                pm05Particles = reader.readLeU16()
                pm1Particles = reader.readLeU16()
                pm25Particles = reader.readLeU16()
                pm10Particles = reader.readLeU16()
                if let tpsRaw = reader.readLeU16() {
                    typicalParticleSize = Double(tpsRaw) / 1000.0
                }
            }
            
            var altitude: Double? = nil
            var satellitesFixed: Int? = nil
            var satellitesView: Int? = nil
            var accuracy: Double? = nil
            if (packetType & GPS_EXT_BIT) != 0 {
                _ = reader.readU8() // snrs
                _ = reader.readU8()
                _ = reader.readU8()
                _ = reader.readU8()
                
                if let altRaw = reader.readLeI16() {
                    altitude = Double(altRaw)
                }
                satellitesFixed = reader.readU8()
                satellitesView = reader.readU8()
                if let accRaw = reader.readLeI16() {
                    accuracy = Double(accRaw) / 100.0
                }
            }
            
            _ = reader.readCrcByte()
            
            let flags = parseFlags(status: status)
            
            list.append(HistoryMeasurement(
                timestamp: Int64(tsSeconds),
                temperature: temp,
                humidity: hum,
                pressure: pressure,
                batteryLevel: batteryU8,
                statusFlags: status,
                vocIndex: vocIndex,
                vocPpb: vocPpb,
                noxIndex: noxIndex,
                co2Ppm: co2Ppm,
                pm1: pm1,
                pm25: pm25,
                pm10: pm10,
                latitude: latitude,
                longitude: longitude,
                pm05Particles: pm05Particles,
                pm1Particles: pm1Particles,
                pm25Particles: pm25Particles,
                pm10Particles: pm10Particles,
                typicalParticleSize: typicalParticleSize,
                altitude: altitude,
                satellitesFixed: satellitesFixed,
                satellitesView: satellitesView,
                accuracy: accuracy,
                flags: flags
            ))
        }
        return list
    }
    
    private static func parseFlags(status: Int) -> [String] {
        let descriptions: [Int: String] = [
            0: "PM sensor error",
            1: "PM laser error",
            2: "PM fan error",
            3: "CO2 error",
            4: "VOC/NOx error",
            5: "Pressure error",
            6: "Accelerometer error",
            7: "Charger error",
            8: "Flash error",
            9: "GPS error",
            10: "External module error",
            12: "Motion",
            13: "PM enabled",
            14: "Charging",
            15: "Recently charged"
        ]
        
        return descriptions.compactMap { (bit, desc) in
            ((status & (1 << bit)) != 0) ? desc : nil
        }
    }
}

class CrcReader {
    private let data: Data
    private var offset: Int = 0
    
    init(data: Data) {
        self.data = data
    }
    
    func readU8() -> Int? {
        guard offset < data.count else { return nil }
        let value = Int(data[offset])
        offset += 1
        return value
    }
    
    func readLeU16() -> Int? {
        guard let b0 = readU8(), let b1 = readU8() else { return nil }
        return b0 | (b1 << 8)
    }
    
    func readLeI16() -> Int16? {
        guard let b0 = readU8(), let b1 = readU8() else { return nil }
        let val = UInt16(b0 | (b1 << 8))
        return Int16(bitPattern: val)
    }
    
    func readLeU32() -> UInt32? {
        guard let b0 = readU8(), let b1 = readU8(), let b2 = readU8(), let b3 = readU8() else { return nil }
        return UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
    }
    
    func readLeI32() -> Int32? {
        guard let b0 = readU8(), let b1 = readU8(), let b2 = readU8(), let b3 = readU8() else { return nil }
        let val = UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
        return Int32(bitPattern: val)
    }
    
    func readCrcByte() -> Int? {
        return readU8()
    }
}

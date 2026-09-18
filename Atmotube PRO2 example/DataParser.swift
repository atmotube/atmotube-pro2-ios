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
    let isCharging: Bool
    let isRecentlyCharged: Bool

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
    
    // Data characteristic (BDA3C092) is 18 bytes:
    // 0-1 temperature, 2 humidity, 3-6 pressure, 7-8 VOC index, 9-10 VOC ppb,
    // 11-12 NOx index, 13-14 CO2 ppm, 15 battery, 16-17 error flags
    // (bit 14 = charging, bit 15 = recently charged; charging overrides temp/humidity)
    static func fromBytes(data: Data, deviceMac: String) -> AtmotubeReading? {
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { return nil }

        let temperatureRaw = Int16(bitPattern: UInt16((Int(bytes[1]) & 0xFF) << 8 | (Int(bytes[0]) & 0xFF)))
        var temperature: Double = (temperatureRaw == Int16.max || temperatureRaw == Int16.max - 1)
            ? Double(temperatureRaw) : Double(temperatureRaw) / 100.0

        let humidityRaw = Int(bytes[2]) & 0xFF
        var humidity = (humidityRaw == 0xFF) ? -1 : humidityRaw

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

        let errorFlags = (Int(bytes[17]) & 0xFF) << 8 | (Int(bytes[16]) & 0xFF)
        let isRecentlyCharged = (errorFlags & (1 << 15)) != 0
        let isCharging = (errorFlags & (1 << 14)) != 0
        if isCharging {
            temperature = Double(Int16.max)
            humidity = -1
        }

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
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            isRecentlyCharged: isRecentlyCharged
        )
    }

    // PM characteristic (BDA3C093) is 16 bytes:
    // 0-1 PM1, 2-3 PM2.5, 4-5 PM10, 6-7 #PM0.5, 8-9 #PM1, 10-11 #PM2.5, 12-13 #PM10,
    // 14-15 typical particle size (µm * 10)
    static func parsePm(data: Data) -> (pm1: Double, pm25: Double, pm10: Double, pm05Particles: Int, pm1Particles: Int, pm25Particles: Int, pm10Particles: Int, typicalParticleSize: Double) {
        let bytes = [UInt8](data)
        if bytes.count < 6 { return (0.0, 0.0, 0.0, 0, 0, 0, 0, 0.0) }

        func readUShort(offset: Int) -> Int {
            return (Int(bytes[offset + 1]) & 0xFF) << 8 | (Int(bytes[offset]) & 0xFF)
        }

        let pm1 = decodePmValue(raw: readUShort(offset: 0))
        let pm25 = decodePmValue(raw: readUShort(offset: 2))
        let pm10 = decodePmValue(raw: readUShort(offset: 4))

        guard bytes.count >= 16 else {
            return (pm1, pm25, pm10, 0, 0, 0, 0, 0.0)
        }

        return (
            pm1: pm1, pm25: pm25, pm10: pm10,
            pm05Particles: readUShort(offset: 6),
            pm1Particles: readUShort(offset: 8),
            pm25Particles: readUShort(offset: 10),
            pm10Particles: readUShort(offset: 12),
            typicalParticleSize: Double(readUShort(offset: 14)) / 10.0
        )
    }
}

struct AtmotubeGpsReading {
    let latitude: Double?
    let longitude: Double?
    let altitude: Int16?
    let satellitesFixed: UInt8?
    let satellitesInView: UInt8?
    let positionError: UInt16?

    // GPS characteristic (BDA3C094) is 18 bytes:
    // 0-3 lat (LE i32, /1e6), 4-7 lon (LE i32, /1e6), 8 snr0-19, 9 snr20-49,
    // 10 snr50-99, 11 snr avg, 12-13 altitude (LE i16), 14 satellites fixed,
    // 15 satellites in view, 16-17 position error (LE u16, raw)
    static func fromBytes(data: Data) -> AtmotubeGpsReading? {
        guard data.count >= 18 else { return nil }
        let bytes = [UInt8](data)

        func readI32(offset: Int) -> Int32 {
            let raw = UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) |
                      (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
            return Int32(bitPattern: raw)
        }
        func readI16(offset: Int) -> Int16 {
            let raw = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            return Int16(bitPattern: raw)
        }
        func readU16(offset: Int) -> UInt16 {
            return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }

        func decodeLat(_ raw: Int32) -> Double? {
            guard raw != 0, raw != .min, raw != .max else { return nil }
            let v = Double(raw) / 1_000_000.0
            return (-90.0...90.0).contains(v) ? v : nil
        }
        func decodeLon(_ raw: Int32) -> Double? {
            guard raw != 0, raw != .min, raw != .max else { return nil }
            let v = Double(raw) / 1_000_000.0
            return (-180.0...180.0).contains(v) ? v : nil
        }

        let altitudeRaw = readI16(offset: 12)
        let satellitesFixedRaw = bytes[14]
        let satellitesInViewRaw = bytes[15]

        return AtmotubeGpsReading(
            latitude: decodeLat(readI32(offset: 0)),
            longitude: decodeLon(readI32(offset: 4)),
            altitude: (altitudeRaw == .min || altitudeRaw == .max) ? nil : altitudeRaw,
            satellitesFixed: (satellitesFixedRaw == .min || satellitesFixedRaw == .max) ? nil : satellitesFixedRaw,
            satellitesInView: (satellitesInViewRaw == .min || satellitesInViewRaw == .max) ? nil : satellitesInViewRaw,
            positionError: readU16(offset: 16)
        )
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
            let recordStart = reader.currentOffset
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
                    typicalParticleSize = Double(tpsRaw) / 10.0
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
                if let accRaw = reader.readLeU16() {
                    accuracy = Double(accRaw)
                }
            }

            let recordEnd = reader.currentOffset
            guard let crcByte = reader.readCrcByte() else { break }
            let computedCrc = crc8Maxim(reader.bytes(from: recordStart, to: recordEnd))
            guard computedCrc == UInt8(crcByte & 0xFF) else {
                print("History record CRC mismatch, discarding record")
                continue
            }

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

func crc8Maxim(_ bytes: [UInt8]) -> UInt8 {
    var crc: UInt8 = 0x00
    for byte in bytes {
        crc ^= byte
        for _ in 0..<8 {
            if (crc & 0x80) != 0 {
                crc = (crc << 1) ^ 0x31
            } else {
                crc <<= 1
            }
        }
    }
    return crc
}

class CrcReader {
    private let data: Data
    private var offset: Int = 0

    var currentOffset: Int { offset }

    func bytes(from start: Int, to end: Int) -> [UInt8] {
        guard start >= 0, end <= data.count, start <= end else { return [] }
        return [UInt8](data[start..<end])
    }

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

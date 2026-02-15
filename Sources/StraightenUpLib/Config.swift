import Foundation

public struct Config: Codable {
    public var interval: Int
    public var threshold: Int
    public var cooldown: Int
    public var neckAngleThreshold: Double
    public var headDropThreshold: Double
    public var forwardOffsetThreshold: Double
    public var shoulderDropThreshold: Double
    public var sound: String
    public var deviceID: String?
    public var verbose: Bool

    public static let `default` = Config(
        interval: 60,
        threshold: 3,
        cooldown: 300,
        neckAngleThreshold: 12.0,
        headDropThreshold: 0.15,
        forwardOffsetThreshold: 0.10,
        shoulderDropThreshold: 0.03,
        sound: "Purr",
        deviceID: nil,
        verbose: false
    )

    public init(interval: Int, threshold: Int, cooldown: Int,
                neckAngleThreshold: Double, headDropThreshold: Double,
                forwardOffsetThreshold: Double, shoulderDropThreshold: Double,
                sound: String, deviceID: String?, verbose: Bool) {
        self.interval = interval
        self.threshold = threshold
        self.cooldown = cooldown
        self.neckAngleThreshold = neckAngleThreshold
        self.headDropThreshold = headDropThreshold
        self.forwardOffsetThreshold = forwardOffsetThreshold
        self.shoulderDropThreshold = shoulderDropThreshold
        self.sound = sound
        self.deviceID = deviceID
        self.verbose = verbose
    }

    // Backward-compatible decoding: handle old config files with angleThreshold/forwardThreshold
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? Config.default.interval
        threshold = try container.decodeIfPresent(Int.self, forKey: .threshold) ?? Config.default.threshold
        cooldown = try container.decodeIfPresent(Int.self, forKey: .cooldown) ?? Config.default.cooldown
        sound = try container.decodeIfPresent(String.self, forKey: .sound) ?? Config.default.sound
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        verbose = try container.decodeIfPresent(Bool.self, forKey: .verbose) ?? Config.default.verbose

        // Try new fields first, fall back to defaults (old fields are ignored — thresholds have changed semantics)
        neckAngleThreshold = try container.decodeIfPresent(Double.self, forKey: .neckAngleThreshold) ?? Config.default.neckAngleThreshold
        headDropThreshold = try container.decodeIfPresent(Double.self, forKey: .headDropThreshold) ?? Config.default.headDropThreshold
        forwardOffsetThreshold = try container.decodeIfPresent(Double.self, forKey: .forwardOffsetThreshold) ?? Config.default.forwardOffsetThreshold
        shoulderDropThreshold = try container.decodeIfPresent(Double.self, forKey: .shoulderDropThreshold) ?? Config.default.shoulderDropThreshold
    }

    public static var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/straighten_up")
    }

    public static var configFile: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    public static var calibrationFile: URL {
        configDirectory.appendingPathComponent("calibration.json")
    }

    public static var logsDirectory: URL {
        configDirectory.appendingPathComponent("logs")
    }

    public static func ensureConfigDirectory() throws {
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )
    }

    public static func ensureLogsDirectory() throws {
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
    }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return .default
        }
        return config
    }

    public func save() throws {
        try Config.ensureConfigDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Config.configFile)
    }

    public static func loadCalibration() -> CalibrationData? {
        guard let data = try? Data(contentsOf: calibrationFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CalibrationData.self, from: data)
    }

    public static func saveCalibration(_ calibration: CalibrationData) throws {
        try ensureConfigDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(calibration)
        try data.write(to: calibrationFile)
    }

    public mutating func applyCommandLineArgs(_ args: [String]) {
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--interval":
                if i + 1 < args.count, let val = Int(args[i + 1]) {
                    interval = val
                    i += 1
                }
            case "--threshold":
                if i + 1 < args.count, let val = Int(args[i + 1]) {
                    threshold = val
                    i += 1
                }
            case "--device":
                if i + 1 < args.count {
                    deviceID = args[i + 1]
                    i += 1
                }
            case "--cooldown":
                if i + 1 < args.count, let val = Int(args[i + 1]) {
                    cooldown = val
                    i += 1
                }
            case "--sound":
                if i + 1 < args.count {
                    sound = args[i + 1]
                    i += 1
                }
            case "--verbose":
                verbose = true
            default:
                break
            }
            i += 1
        }
    }
}

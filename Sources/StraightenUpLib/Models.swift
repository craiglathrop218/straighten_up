import Foundation

public struct JointPoint: Codable {
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public struct CalibrationData: Codable {
    public let timestamp: Date
    public let side: String
    public let baselineNeckAngle: Double
    public let baselineHeadShoulderRatio: Double
    public let baselineForwardOffset: Double
    public let baselineShoulderDrop: Double?
    public let availableMetrics: [String]

    public init(timestamp: Date, side: String, baselineNeckAngle: Double,
                baselineHeadShoulderRatio: Double, baselineForwardOffset: Double,
                baselineShoulderDrop: Double?, availableMetrics: [String]) {
        self.timestamp = timestamp
        self.side = side
        self.baselineNeckAngle = baselineNeckAngle
        self.baselineHeadShoulderRatio = baselineHeadShoulderRatio
        self.baselineForwardOffset = baselineForwardOffset
        self.baselineShoulderDrop = baselineShoulderDrop
        self.availableMetrics = availableMetrics
    }
}

public struct PostureAssessment {
    public let isGoodPosture: Bool
    public let compositeScore: Double
    public let neckAngleDeviation: Double?
    public let headDropDeviation: Double?
    public let forwardOffsetDeviation: Double?
    public let shoulderDropDeviation: Double?
    public let metricsUsed: [String]
    public let details: String
}

public struct CameraInfo {
    public let id: String
    public let name: String
    public let manufacturer: String
    public let isActive: Bool
}

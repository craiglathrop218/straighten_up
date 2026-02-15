import Foundation

public struct PostureAnalyzer {
    private static let usableConfidence: Double = 0.3

    // MARK: - Joint Selection

    public static func determineSide(joints: [String: JointPoint]) -> String {
        let leftKeys = ["left_ear", "left_shoulder"]
        let rightKeys = ["right_ear", "right_shoulder"]

        let leftConfidence = leftKeys.compactMap { joints[$0]?.confidence }.reduce(0, +)
        let rightConfidence = rightKeys.compactMap { joints[$0]?.confidence }.reduce(0, +)

        return leftConfidence >= rightConfidence ? "left" : "right"
    }

    public struct SelectedJoints {
        public let side: String
        public let ear: JointPoint?
        public let shoulder: JointPoint?
        public let neck: JointPoint?
        public let nose: JointPoint?
        public let leftShoulder: JointPoint?
        public let rightShoulder: JointPoint?
    }

    public static func selectJoints(from joints: [String: JointPoint]) -> SelectedJoints {
        let side = determineSide(joints: joints)
        let earKey = "\(side)_ear"
        let shoulderKey = "\(side)_shoulder"

        func usable(_ key: String) -> JointPoint? {
            guard let j = joints[key], j.confidence >= usableConfidence else { return nil }
            return j
        }

        return SelectedJoints(
            side: side,
            ear: usable(earKey),
            shoulder: usable(shoulderKey),
            neck: usable("neck"),
            nose: usable("nose"),
            leftShoulder: usable("left_shoulder"),
            rightShoulder: usable("right_shoulder")
        )
    }

    // MARK: - Individual Metrics

    /// Neck inclination: angle of neck→head vector from vertical (degrees).
    /// 0° = head directly above neck. Forward slouch increases this.
    public static func neckInclination(neck: JointPoint, head: JointPoint) -> Double {
        let dx = head.x - neck.x
        let dy = head.y - neck.y
        let angleRad = atan2(abs(dx), dy) // dy positive = upward in Vision coords
        return angleRad * 180.0 / .pi
    }

    /// Head-shoulder vertical ratio: vertical distance from head to shoulder,
    /// normalized by shoulder width when available.
    public static func headShoulderRatio(head: JointPoint, shoulder: JointPoint,
                                          leftShoulder: JointPoint?, rightShoulder: JointPoint?) -> Double {
        let verticalGap = head.y - shoulder.y

        if let ls = leftShoulder, let rs = rightShoulder {
            let shoulderWidth = abs(ls.x - rs.x)
            if shoulderWidth > 0.01 {
                return verticalGap / shoulderWidth
            }
        }

        return verticalGap
    }

    /// Ear-shoulder forward offset: horizontal offset of ear from shoulder,
    /// normalized by ear-shoulder vertical distance. Side-aware sign correction.
    public static func earShoulderForwardOffset(ear: JointPoint, shoulder: JointPoint, side: String) -> Double {
        let dx = ear.x - shoulder.x
        let dy = ear.y - shoulder.y
        let verticalDist = max(abs(dy), 0.01)

        // Sign correction: for left side, forward = positive x offset
        // For right side, forward = negative x offset
        let signedOffset = side == "left" ? dx : -dx
        return signedOffset / verticalDist
    }

    /// Shoulder symmetry: Y difference between left and right shoulders.
    public static func shoulderDrop(leftShoulder: JointPoint, rightShoulder: JointPoint) -> Double {
        return abs(leftShoulder.y - rightShoulder.y)
    }

    // MARK: - Calibration

    public static func calibrate(joints: [String: JointPoint]) throws -> CalibrationData {
        let sel = selectJoints(from: joints)

        // Determine best head point: prefer nose, fall back to ear
        let headPoint = sel.nose ?? sel.ear

        var metrics: [String] = []
        var baseNeckAngle = 0.0
        var baseHeadShoulderRatio = 0.0
        var baseForwardOffset = 0.0
        var baseShoulderDrop: Double? = nil

        // Neck angle: requires neck + head point
        if let neck = sel.neck, let head = headPoint {
            baseNeckAngle = neckInclination(neck: neck, head: head)
            metrics.append("neckAngle")
        }

        // Head-shoulder ratio: requires head + shoulder
        if let head = headPoint, let shoulder = sel.shoulder {
            baseHeadShoulderRatio = headShoulderRatio(
                head: head, shoulder: shoulder,
                leftShoulder: sel.leftShoulder, rightShoulder: sel.rightShoulder
            )
            metrics.append("headShoulderRatio")
        }

        // Forward offset: requires ear + shoulder
        if let ear = sel.ear, let shoulder = sel.shoulder {
            baseForwardOffset = earShoulderForwardOffset(ear: ear, shoulder: shoulder, side: sel.side)
            metrics.append("forwardOffset")
        }

        // Shoulder drop: requires both shoulders
        if let ls = sel.leftShoulder, let rs = sel.rightShoulder {
            baseShoulderDrop = shoulderDrop(leftShoulder: ls, rightShoulder: rs)
            metrics.append("shoulderDrop")
        }

        guard metrics.count >= 2 else {
            let available = joints.keys.sorted().joined(separator: ", ")
            throw StraightenUpError.insufficientJoints(
                "Need at least 2 computable metrics, got \(metrics.count). Available joints: \(available)"
            )
        }

        return CalibrationData(
            timestamp: Date(),
            side: sel.side,
            baselineNeckAngle: baseNeckAngle,
            baselineHeadShoulderRatio: baseHeadShoulderRatio,
            baselineForwardOffset: baseForwardOffset,
            baselineShoulderDrop: baseShoulderDrop,
            availableMetrics: metrics
        )
    }

    // MARK: - Assessment

    public static func assess(joints: [String: JointPoint], calibration: CalibrationData, config: Config) -> PostureAssessment {
        let sel = selectJoints(from: joints)
        let headPoint = sel.nose ?? sel.ear

        struct MetricResult {
            let name: String
            let weight: Double
            let deviation: Double
            let threshold: Double
            var score: Double { deviation / threshold }
        }

        var results: [MetricResult] = []

        // Neck angle
        if calibration.availableMetrics.contains("neckAngle"),
           let neck = sel.neck, let head = headPoint {
            let current = neckInclination(neck: neck, head: head)
            let deviation = abs(current - calibration.baselineNeckAngle)
            results.append(MetricResult(name: "neckAngle", weight: 0.35, deviation: deviation, threshold: config.neckAngleThreshold))
        }

        // Head-shoulder ratio
        if calibration.availableMetrics.contains("headShoulderRatio"),
           let head = headPoint, let shoulder = sel.shoulder {
            let current = headShoulderRatio(
                head: head, shoulder: shoulder,
                leftShoulder: sel.leftShoulder, rightShoulder: sel.rightShoulder
            )
            let deviation = max(0, calibration.baselineHeadShoulderRatio - current) // slouching reduces ratio
            let threshold = (sel.leftShoulder != nil && sel.rightShoulder != nil) ? config.headDropThreshold : 0.04
            results.append(MetricResult(name: "headShoulderRatio", weight: 0.30, deviation: deviation, threshold: threshold))
        }

        // Forward offset
        if calibration.availableMetrics.contains("forwardOffset"),
           let ear = sel.ear, let shoulder = sel.shoulder {
            let current = earShoulderForwardOffset(ear: ear, shoulder: shoulder, side: sel.side)
            let deviation = max(0, current - calibration.baselineForwardOffset) // forward head increases offset
            results.append(MetricResult(name: "forwardOffset", weight: 0.25, deviation: deviation, threshold: config.forwardOffsetThreshold))
        }

        // Shoulder drop
        if calibration.availableMetrics.contains("shoulderDrop"),
           let baseDrop = calibration.baselineShoulderDrop,
           let ls = sel.leftShoulder, let rs = sel.rightShoulder {
            let current = shoulderDrop(leftShoulder: ls, rightShoulder: rs)
            let deviation = abs(current - baseDrop)
            results.append(MetricResult(name: "shoulderDrop", weight: 0.10, deviation: deviation, threshold: config.shoulderDropThreshold))
        }

        // Need at least 2 metrics to make an assessment
        guard results.count >= 2 else {
            return PostureAssessment(
                isGoodPosture: true,
                compositeScore: 0,
                neckAngleDeviation: nil,
                headDropDeviation: nil,
                forwardOffsetDeviation: nil,
                shoulderDropDeviation: nil,
                metricsUsed: results.map { $0.name },
                details: "Insufficient metrics (\(results.count)) — skipping frame"
            )
        }

        // Composite score: redistribute weights among available metrics
        let totalWeight = results.reduce(0) { $0 + $1.weight }
        let compositeScore = results.reduce(0) { $0 + ($1.weight / totalWeight) * $1.score }

        // Bad posture = composite >= 1.0 OR any single metric > 1.5x threshold
        let anyExtreme = results.contains { $0.score > 1.5 }
        let isGood = compositeScore < 1.0 && !anyExtreme

        // Extract individual deviations for output
        func deviationFor(_ name: String) -> Double? {
            results.first(where: { $0.name == name })?.deviation
        }

        // Build details string
        var detailParts: [String] = []
        for r in results {
            let status = r.score >= 1.0 ? "!" : (r.score >= 0.7 ? "~" : "ok")
            detailParts.append("\(r.name): \(String(format: "%.2f", r.deviation))/\(String(format: "%.2f", r.threshold)) [\(status)]")
        }
        var details = "Score: \(String(format: "%.2f", compositeScore)) | \(detailParts.joined(separator: " | "))"
        if !isGood {
            let badMetrics = results.filter { $0.score >= 1.0 }.map { $0.name }
            if !badMetrics.isEmpty {
                details += " [BAD: \(badMetrics.joined(separator: ", "))]"
            }
        }

        return PostureAssessment(
            isGoodPosture: isGood,
            compositeScore: compositeScore,
            neckAngleDeviation: deviationFor("neckAngle"),
            headDropDeviation: deviationFor("headShoulderRatio"),
            forwardOffsetDeviation: deviationFor("forwardOffset"),
            shoulderDropDeviation: deviationFor("shoulderDrop"),
            metricsUsed: results.map { $0.name },
            details: details
        )
    }
}

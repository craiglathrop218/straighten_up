import Foundation
import StraightenUpLib

var passed = 0
var failed = 0

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        passed += 1
        print("  PASS: \(name)")
    } catch {
        failed += 1
        print("  FAIL: \(name) - \(error)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "") throws {
    guard a == b else {
        throw TestError.assertion("\(msg) Expected \(b), got \(a)")
    }
}

func assertApprox(_ a: Double, _ b: Double, accuracy: Double = 0.1, _ msg: String = "") throws {
    guard abs(a - b) < accuracy else {
        throw TestError.assertion("\(msg) Expected ~\(b), got \(a) (tolerance \(accuracy))")
    }
}

func assertTrue(_ value: Bool, _ msg: String = "") throws {
    guard value else {
        throw TestError.assertion(msg.isEmpty ? "Expected true, got false" : msg)
    }
}

func assertFalse(_ value: Bool, _ msg: String = "") throws {
    guard !value else {
        throw TestError.assertion(msg.isEmpty ? "Expected false, got true" : msg)
    }
}

enum TestError: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self { case .assertion(let msg): return msg }
    }
}

// ============================================================
// Neck Inclination Tests
// ============================================================
print("Neck Inclination Tests:")

test("Head directly above neck is 0 degrees") {
    let neck = JointPoint(x: 0.5, y: 0.6, confidence: 1.0)
    let head = JointPoint(x: 0.5, y: 0.8, confidence: 1.0)
    let angle = PostureAnalyzer.neckInclination(neck: neck, head: head)
    try assertApprox(angle, 0.0, accuracy: 0.01)
}

test("Head tilted forward gives positive angle") {
    let neck = JointPoint(x: 0.5, y: 0.6, confidence: 1.0)
    let head = JointPoint(x: 0.6, y: 0.8, confidence: 1.0)
    let angle = PostureAnalyzer.neckInclination(neck: neck, head: head)
    try assertTrue(angle > 0, "Should be positive, got \(angle)")
    try assertApprox(angle, 26.57, accuracy: 0.1) // atan2(0.1, 0.2) in degrees
}

test("45-degree neck tilt") {
    let neck = JointPoint(x: 0.5, y: 0.5, confidence: 1.0)
    let head = JointPoint(x: 0.7, y: 0.7, confidence: 1.0)
    let angle = PostureAnalyzer.neckInclination(neck: neck, head: head)
    try assertApprox(angle, 45.0, accuracy: 0.1)
}

// ============================================================
// Head-Shoulder Ratio Tests
// ============================================================
print("\nHead-Shoulder Ratio Tests:")

test("Normalized ratio with both shoulders") {
    let head = JointPoint(x: 0.5, y: 0.8, confidence: 1.0)
    let shoulder = JointPoint(x: 0.5, y: 0.6, confidence: 1.0)
    let ls = JointPoint(x: 0.3, y: 0.6, confidence: 1.0)
    let rs = JointPoint(x: 0.7, y: 0.6, confidence: 1.0)
    let ratio = PostureAnalyzer.headShoulderRatio(head: head, shoulder: shoulder, leftShoulder: ls, rightShoulder: rs)
    // verticalGap = 0.2, shoulderWidth = 0.4 → ratio = 0.5
    try assertApprox(ratio, 0.5, accuracy: 0.01)
}

test("Raw ratio without both shoulders") {
    let head = JointPoint(x: 0.5, y: 0.8, confidence: 1.0)
    let shoulder = JointPoint(x: 0.5, y: 0.6, confidence: 1.0)
    let ratio = PostureAnalyzer.headShoulderRatio(head: head, shoulder: shoulder, leftShoulder: nil, rightShoulder: nil)
    // Just vertical gap = 0.2
    try assertApprox(ratio, 0.2, accuracy: 0.01)
}

test("Slouched ratio is smaller") {
    let ls = JointPoint(x: 0.3, y: 0.6, confidence: 1.0)
    let rs = JointPoint(x: 0.7, y: 0.6, confidence: 1.0)
    let shoulder = JointPoint(x: 0.5, y: 0.6, confidence: 1.0)

    let goodHead = JointPoint(x: 0.5, y: 0.8, confidence: 1.0)
    let slouchHead = JointPoint(x: 0.5, y: 0.7, confidence: 1.0)

    let goodRatio = PostureAnalyzer.headShoulderRatio(head: goodHead, shoulder: shoulder, leftShoulder: ls, rightShoulder: rs)
    let slouchRatio = PostureAnalyzer.headShoulderRatio(head: slouchHead, shoulder: shoulder, leftShoulder: ls, rightShoulder: rs)

    try assertTrue(slouchRatio < goodRatio, "Slouched ratio \(slouchRatio) should be < good ratio \(goodRatio)")
}

// ============================================================
// Ear-Shoulder Forward Offset Tests
// ============================================================
print("\nEar-Shoulder Forward Offset Tests:")

test("Ear aligned with shoulder is zero offset") {
    let ear = JointPoint(x: 0.5, y: 0.8, confidence: 1.0)
    let shoulder = JointPoint(x: 0.5, y: 0.6, confidence: 1.0)
    let offset = PostureAnalyzer.earShoulderForwardOffset(ear: ear, shoulder: shoulder, side: "left")
    try assertApprox(offset, 0.0, accuracy: 0.01)
}

test("Left side forward offset positive when ear ahead") {
    let ear = JointPoint(x: 0.6, y: 0.8, confidence: 1.0)
    let shoulder = JointPoint(x: 0.5, y: 0.6, confidence: 1.0)
    let offset = PostureAnalyzer.earShoulderForwardOffset(ear: ear, shoulder: shoulder, side: "left")
    try assertTrue(offset > 0, "Left-side forward offset should be positive, got \(offset)")
    // dx=0.1, dy=0.2, offset = 0.1/0.2 = 0.5
    try assertApprox(offset, 0.5, accuracy: 0.01)
}

test("Right side forward offset positive when ear ahead") {
    let ear = JointPoint(x: 0.4, y: 0.8, confidence: 1.0)
    let shoulder = JointPoint(x: 0.5, y: 0.6, confidence: 1.0)
    let offset = PostureAnalyzer.earShoulderForwardOffset(ear: ear, shoulder: shoulder, side: "right")
    try assertTrue(offset > 0, "Right-side forward offset should be positive, got \(offset)")
    try assertApprox(offset, 0.5, accuracy: 0.01)
}

// ============================================================
// Shoulder Drop Tests
// ============================================================
print("\nShoulder Drop Tests:")

test("Level shoulders have zero drop") {
    let ls = JointPoint(x: 0.3, y: 0.6, confidence: 1.0)
    let rs = JointPoint(x: 0.7, y: 0.6, confidence: 1.0)
    let drop = PostureAnalyzer.shoulderDrop(leftShoulder: ls, rightShoulder: rs)
    try assertApprox(drop, 0.0, accuracy: 0.001)
}

test("Uneven shoulders have nonzero drop") {
    let ls = JointPoint(x: 0.3, y: 0.62, confidence: 1.0)
    let rs = JointPoint(x: 0.7, y: 0.58, confidence: 1.0)
    let drop = PostureAnalyzer.shoulderDrop(leftShoulder: ls, rightShoulder: rs)
    try assertApprox(drop, 0.04, accuracy: 0.001)
}

// ============================================================
// Joint Selection Tests
// ============================================================
print("\nJoint Selection Tests:")

test("Determine left side with higher confidence") {
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.3, y: 0.9, confidence: 0.9),
        "left_shoulder": JointPoint(x: 0.3, y: 0.6, confidence: 0.9),
        "right_ear": JointPoint(x: 0.7, y: 0.9, confidence: 0.3),
        "right_shoulder": JointPoint(x: 0.7, y: 0.6, confidence: 0.3),
    ]
    try assertEqual(PostureAnalyzer.determineSide(joints: joints), "left")
}

test("Determine right side with higher confidence") {
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.3, y: 0.9, confidence: 0.2),
        "left_shoulder": JointPoint(x: 0.3, y: 0.6, confidence: 0.2),
        "right_ear": JointPoint(x: 0.7, y: 0.9, confidence: 0.8),
        "right_shoulder": JointPoint(x: 0.7, y: 0.6, confidence: 0.8),
    ]
    try assertEqual(PostureAnalyzer.determineSide(joints: joints), "right")
}

test("Select joints filters by confidence") {
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.3, y: 0.9, confidence: 0.5),
        "left_shoulder": JointPoint(x: 0.3, y: 0.6, confidence: 0.5),
        "neck": JointPoint(x: 0.5, y: 0.65, confidence: 0.1), // below threshold
        "nose": JointPoint(x: 0.5, y: 0.85, confidence: 0.8),
    ]
    let sel = PostureAnalyzer.selectJoints(from: joints)
    try assertEqual(sel.side, "left")
    try assertTrue(sel.ear != nil, "ear should be selected")
    try assertTrue(sel.shoulder != nil, "shoulder should be selected")
    try assertTrue(sel.neck == nil, "neck should be filtered out (low confidence)")
    try assertTrue(sel.nose != nil, "nose should be selected")
}

// ============================================================
// Calibration Tests
// ============================================================
print("\nCalibration Tests:")

test("Calibration with full upper-body joints") {
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.5, y: 0.85, confidence: 0.9),
        "left_shoulder": JointPoint(x: 0.5, y: 0.6, confidence: 0.9),
        "right_shoulder": JointPoint(x: 0.7, y: 0.6, confidence: 0.5),
        "neck": JointPoint(x: 0.5, y: 0.65, confidence: 0.8),
        "nose": JointPoint(x: 0.5, y: 0.85, confidence: 0.9),
    ]
    let cal = try PostureAnalyzer.calibrate(joints: joints)
    try assertEqual(cal.side, "left")
    try assertTrue(cal.availableMetrics.count >= 3, "Should have at least 3 metrics, got \(cal.availableMetrics)")
    try assertTrue(cal.availableMetrics.contains("neckAngle"))
    try assertTrue(cal.availableMetrics.contains("headShoulderRatio"))
    try assertTrue(cal.availableMetrics.contains("forwardOffset"))
}

test("Calibration fails with insufficient joints") {
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.3, y: 0.9, confidence: 0.5),
        // No shoulder, no neck, no nose → only 0 computable metrics
    ]
    do {
        _ = try PostureAnalyzer.calibrate(joints: joints)
        throw TestError.assertion("Should have thrown insufficientJoints")
    } catch is TestError {
        throw TestError.assertion("Should have thrown insufficientJoints")
    } catch {
        // Expected
    }
}

test("Calibration with no hips still succeeds") {
    // The key test: upper-body-only works without hip joints
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.5, y: 0.85, confidence: 0.8),
        "left_shoulder": JointPoint(x: 0.5, y: 0.6, confidence: 0.8),
        "neck": JointPoint(x: 0.5, y: 0.65, confidence: 0.7),
        "nose": JointPoint(x: 0.5, y: 0.87, confidence: 0.9),
    ]
    let cal = try PostureAnalyzer.calibrate(joints: joints)
    try assertTrue(cal.availableMetrics.count >= 2, "Should succeed with upper-body only")
    try assertFalse(cal.availableMetrics.contains("shoulderDrop"), "Should not have shoulder drop with one shoulder")
}

// ============================================================
// Assessment Tests
// ============================================================
print("\nAssessment Tests:")

test("Good posture assessed correctly") {
    let calibration = CalibrationData(
        timestamp: Date(), side: "left",
        baselineNeckAngle: 5.0, baselineHeadShoulderRatio: 0.5,
        baselineForwardOffset: 0.1, baselineShoulderDrop: nil,
        availableMetrics: ["neckAngle", "headShoulderRatio", "forwardOffset"]
    )
    // Same posture as calibration
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.5, y: 0.85, confidence: 0.9),
        "left_shoulder": JointPoint(x: 0.5, y: 0.6, confidence: 0.9),
        "right_shoulder": JointPoint(x: 0.7, y: 0.6, confidence: 0.5),
        "neck": JointPoint(x: 0.5, y: 0.65, confidence: 0.8),
        "nose": JointPoint(x: 0.5, y: 0.85, confidence: 0.9),
    ]
    let assessment = PostureAnalyzer.assess(
        joints: joints, calibration: calibration, config: .default
    )
    try assertTrue(assessment.isGoodPosture, "Should be good posture. Details: \(assessment.details)")
    try assertTrue(assessment.compositeScore < 1.0, "Composite should be < 1.0, got \(assessment.compositeScore)")
}

test("Bad posture from forward head detected") {
    let calibration = CalibrationData(
        timestamp: Date(), side: "left",
        baselineNeckAngle: 2.0, baselineHeadShoulderRatio: 0.5,
        baselineForwardOffset: 0.05, baselineShoulderDrop: nil,
        availableMetrics: ["neckAngle", "headShoulderRatio", "forwardOffset"]
    )
    // Head way forward
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.7, y: 0.75, confidence: 0.9),
        "left_shoulder": JointPoint(x: 0.5, y: 0.6, confidence: 0.9),
        "right_shoulder": JointPoint(x: 0.7, y: 0.6, confidence: 0.5),
        "neck": JointPoint(x: 0.5, y: 0.65, confidence: 0.8),
        "nose": JointPoint(x: 0.7, y: 0.78, confidence: 0.9),
    ]
    let assessment = PostureAnalyzer.assess(
        joints: joints, calibration: calibration, config: .default
    )
    try assertFalse(assessment.isGoodPosture, "Should detect bad posture. Score: \(assessment.compositeScore), Details: \(assessment.details)")
}

test("Insufficient metrics returns good posture (skip frame)") {
    let calibration = CalibrationData(
        timestamp: Date(), side: "left",
        baselineNeckAngle: 5.0, baselineHeadShoulderRatio: 0.5,
        baselineForwardOffset: 0.1, baselineShoulderDrop: nil,
        availableMetrics: ["neckAngle", "headShoulderRatio", "forwardOffset"]
    )
    // Only one usable joint → can't compute 2 metrics
    let joints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.5, y: 0.85, confidence: 0.9),
    ]
    let assessment = PostureAnalyzer.assess(
        joints: joints, calibration: calibration, config: .default
    )
    try assertTrue(assessment.isGoodPosture, "Should skip frame when insufficient metrics")
    try assertTrue(assessment.details.contains("Insufficient"), "Details should mention insufficient metrics")
}

test("Composite score increases with slouch severity") {
    let calibration = CalibrationData(
        timestamp: Date(), side: "left",
        baselineNeckAngle: 0.0, baselineHeadShoulderRatio: 0.5,
        baselineForwardOffset: 0.0, baselineShoulderDrop: nil,
        availableMetrics: ["neckAngle", "headShoulderRatio", "forwardOffset"]
    )

    // Mild slouch
    let mildJoints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.52, y: 0.82, confidence: 0.9),
        "left_shoulder": JointPoint(x: 0.5, y: 0.6, confidence: 0.9),
        "right_shoulder": JointPoint(x: 0.7, y: 0.6, confidence: 0.5),
        "neck": JointPoint(x: 0.5, y: 0.65, confidence: 0.8),
        "nose": JointPoint(x: 0.52, y: 0.84, confidence: 0.9),
    ]

    // Severe slouch
    let severeJoints: [String: JointPoint] = [
        "left_ear": JointPoint(x: 0.7, y: 0.72, confidence: 0.9),
        "left_shoulder": JointPoint(x: 0.5, y: 0.6, confidence: 0.9),
        "right_shoulder": JointPoint(x: 0.7, y: 0.6, confidence: 0.5),
        "neck": JointPoint(x: 0.5, y: 0.65, confidence: 0.8),
        "nose": JointPoint(x: 0.7, y: 0.75, confidence: 0.9),
    ]

    let mildAssessment = PostureAnalyzer.assess(joints: mildJoints, calibration: calibration, config: .default)
    let severeAssessment = PostureAnalyzer.assess(joints: severeJoints, calibration: calibration, config: .default)

    try assertTrue(severeAssessment.compositeScore > mildAssessment.compositeScore,
        "Severe slouch score \(severeAssessment.compositeScore) should be > mild \(mildAssessment.compositeScore)")
}

// ============================================================
// Config Tests
// ============================================================
print("\nConfig Tests:")

test("Default config values") {
    let config = Config.default
    try assertEqual(config.interval, 60)
    try assertEqual(config.threshold, 3)
    try assertEqual(config.cooldown, 300)
    try assertApprox(config.neckAngleThreshold, 12.0, accuracy: 0.01)
    try assertApprox(config.headDropThreshold, 0.15, accuracy: 0.01)
    try assertApprox(config.forwardOffsetThreshold, 0.10, accuracy: 0.01)
    try assertApprox(config.shoulderDropThreshold, 0.03, accuracy: 0.01)
    try assertEqual(config.sound, "Purr")
    try assertTrue(config.deviceID == nil, "deviceID should be nil")
    try assertFalse(config.verbose)
}

test("Config serialization round-trip") {
    let original = Config(
        interval: 30, threshold: 5, cooldown: 600,
        neckAngleThreshold: 15.0, headDropThreshold: 0.20,
        forwardOffsetThreshold: 0.12, shoulderDropThreshold: 0.05,
        sound: "Glass", deviceID: "test-device-123", verbose: true
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Config.self, from: data)
    try assertEqual(decoded.interval, original.interval)
    try assertEqual(decoded.threshold, original.threshold)
    try assertEqual(decoded.cooldown, original.cooldown)
    try assertApprox(decoded.neckAngleThreshold, original.neckAngleThreshold, accuracy: 0.001)
    try assertApprox(decoded.headDropThreshold, original.headDropThreshold, accuracy: 0.001)
    try assertApprox(decoded.forwardOffsetThreshold, original.forwardOffsetThreshold, accuracy: 0.001)
    try assertApprox(decoded.shoulderDropThreshold, original.shoulderDropThreshold, accuracy: 0.001)
    try assertEqual(decoded.sound, original.sound)
    try assertEqual(decoded.deviceID, original.deviceID)
    try assertEqual(decoded.verbose, original.verbose)
}

test("Backward-compatible config loading (old fields ignored)") {
    // Simulate an old config with angleThreshold and forwardThreshold
    let oldJSON = """
    {
        "interval": 45,
        "threshold": 2,
        "cooldown": 120,
        "angleThreshold": 15.0,
        "forwardThreshold": 0.08,
        "sound": "Tink",
        "verbose": true
    }
    """.data(using: .utf8)!
    let config = try JSONDecoder().decode(Config.self, from: oldJSON)
    try assertEqual(config.interval, 45)
    try assertEqual(config.threshold, 2)
    try assertEqual(config.cooldown, 120)
    try assertEqual(config.sound, "Tink")
    try assertTrue(config.verbose)
    // New thresholds should get defaults since old fields are different keys
    try assertApprox(config.neckAngleThreshold, 12.0, accuracy: 0.01)
    try assertApprox(config.headDropThreshold, 0.15, accuracy: 0.01)
    try assertApprox(config.forwardOffsetThreshold, 0.10, accuracy: 0.01)
}

test("Command line args override config") {
    var config = Config.default
    config.applyCommandLineArgs([
        "monitor", "--interval", "30", "--threshold", "5",
        "--cooldown", "600", "--device", "my-camera",
        "--sound", "Glass", "--verbose"
    ])
    try assertEqual(config.interval, 30)
    try assertEqual(config.threshold, 5)
    try assertEqual(config.cooldown, 600)
    try assertEqual(config.deviceID, "my-camera")
    try assertEqual(config.sound, "Glass")
    try assertTrue(config.verbose)
}

test("Partial command line args preserve defaults") {
    var config = Config.default
    config.applyCommandLineArgs(["--verbose", "--interval", "10"])
    try assertEqual(config.interval, 10)
    try assertTrue(config.verbose)
    try assertEqual(config.threshold, 3)
    try assertEqual(config.cooldown, 300)
    try assertEqual(config.sound, "Purr")
}

test("Calibration data serialization round-trip") {
    let original = CalibrationData(
        timestamp: Date(), side: "left",
        baselineNeckAngle: 5.2, baselineHeadShoulderRatio: 0.48,
        baselineForwardOffset: 0.12, baselineShoulderDrop: 0.02,
        availableMetrics: ["neckAngle", "headShoulderRatio", "forwardOffset", "shoulderDrop"]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(CalibrationData.self, from: data)
    try assertApprox(decoded.baselineNeckAngle, original.baselineNeckAngle, accuracy: 0.001)
    try assertApprox(decoded.baselineHeadShoulderRatio, original.baselineHeadShoulderRatio, accuracy: 0.001)
    try assertApprox(decoded.baselineForwardOffset, original.baselineForwardOffset, accuracy: 0.001)
    try assertApprox(decoded.baselineShoulderDrop!, original.baselineShoulderDrop!, accuracy: 0.001)
    try assertEqual(decoded.side, original.side)
    try assertEqual(decoded.availableMetrics, original.availableMetrics)
}

// ============================================================
// Summary
// ============================================================
print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}

import Foundation
import StraightenUpLib

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "monitor"

var config = Config.load()
config.applyCommandLineArgs(args)

func printUsage() {
    print("""
    Usage: StraightenUp [command] [options]

    Commands:
      monitor        Start posture monitoring (default)
      calibrate      Capture baseline "good posture" snapshot
      diagnose       Capture one frame and dump all detected joints
      list-cameras   Show available camera devices
      status         Show current config and calibration info
      help           Show this help message

    Options:
      --interval <seconds>       Check interval (default: 60)
      --threshold <count>        Consecutive bad readings before alert (default: 3)
      --device <id>              Camera device ID (from list-cameras)
      --cooldown <seconds>       Min time between alerts (default: 300)
      --sound <name>             Alert sound name (default: "Purr")
      --verbose                  Enable detailed logging
    """)
}

func listCameras() {
    let cameras = CameraCapture.listCameras()
    if cameras.isEmpty {
        print("No cameras found.")
        return
    }
    print("Available cameras:\n")
    for (i, cam) in cameras.enumerated() {
        print("  \(i + 1). \(cam.name)")
        print("     ID: \(cam.id)")
        print("     Manufacturer: \(cam.manufacturer)")
        print("     Active: \(cam.isActive ? "Yes" : "No")")
        print()
    }
}

func showStatus() {
    print("StraightenUp Status\n")

    print("Configuration:")
    print("  Config file: \(Config.configFile.path)")
    print("  Interval: \(config.interval)s")
    print("  Threshold: \(config.threshold) consecutive readings")
    print("  Cooldown: \(config.cooldown)s")
    print("  Neck angle threshold: \(config.neckAngleThreshold)°")
    print("  Head drop threshold: \(config.headDropThreshold)")
    print("  Forward offset threshold: \(config.forwardOffsetThreshold)")
    print("  Shoulder drop threshold: \(config.shoulderDropThreshold)")
    print("  Sound: \(config.sound)")
    print("  Device: \(config.deviceID ?? "default")")
    print("  Verbose: \(config.verbose)")
    print()

    if let cal = Config.loadCalibration() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        print("Calibration:")
        print("  File: \(Config.calibrationFile.path)")
        print("  Date: \(formatter.string(from: cal.timestamp))")
        print("  Side: \(cal.side)")
        print("  Metrics: \(cal.availableMetrics.joined(separator: ", "))")
        print("  Baseline neck angle: \(String(format: "%.1f", cal.baselineNeckAngle))°")
        print("  Baseline head-shoulder ratio: \(String(format: "%.3f", cal.baselineHeadShoulderRatio))")
        print("  Baseline forward offset: \(String(format: "%.3f", cal.baselineForwardOffset))")
        if let drop = cal.baselineShoulderDrop {
            print("  Baseline shoulder drop: \(String(format: "%.3f", drop))")
        }
    } else {
        print("Calibration: Not calibrated")
        print("  Run 'StraightenUp calibrate' to set your baseline posture.")
    }
}

func diagnose(config: Config) async {
    print("Camera Diagnostics")
    print("==================\n")
    print("Capturing frame...")

    let timestamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")

    do {
        try Config.ensureLogsDirectory()
    } catch {
        print("Warning: Could not create logs directory: \(error)")
    }

    do {
        let camera = CameraCapture()
        let sampleBuffer = try await camera.captureFrame(deviceID: config.deviceID)

        // Save the raw image
        let imageFile = Config.logsDirectory.appendingPathComponent("diagnose_\(timestamp).jpg")
        if PoseDetector.saveImage(from: sampleBuffer, to: imageFile) {
            print("Saved frame: \(imageFile.path)")
        } else {
            print("Warning: Could not save frame image")
        }

        let result = PoseDetector.diagnose(from: sampleBuffer)

        print("Image: \(result.imageWidth)x\(result.imageHeight)")
        print("Pose detected: \(result.poseDetected)\n")

        // Build JSON diagnostic report
        var report: [String: Any] = [
            "timestamp": timestamp,
            "imageWidth": result.imageWidth,
            "imageHeight": result.imageHeight,
            "poseDetected": result.poseDetected,
        ]

        if result.poseDetected {
            print("All joints:")
            var jointsList: [[String: Any]] = []
            for detail in result.allJointDetails.sorted(by: { $0.confidence > $1.confidence }) {
                let conf = String(format: "%.3f", detail.confidence)
                let usable = detail.confidence >= 0.3 ? "  usable" : ""
                print("  \(detail.name.padding(toLength: 16, withPad: " ", startingAt: 0)) x=\(String(format: "%.3f", detail.x)) y=\(String(format: "%.3f", detail.y)) conf=\(conf)\(usable)")
                jointsList.append([
                    "name": detail.name,
                    "x": detail.x,
                    "y": detail.y,
                    "confidence": detail.confidence,
                    "usable": detail.confidence >= 0.3,
                ])
            }
            report["joints"] = jointsList

            print("\nUsable joints (conf >= 0.3): \(result.joints.count)")
            let upperBody = ["nose", "neck", "left_ear", "right_ear", "left_shoulder", "right_shoulder"]
            let usableUpper = upperBody.filter { result.joints[$0] != nil }
            print("Usable upper-body: \(usableUpper.joined(separator: ", "))")

            // Try calibration
            do {
                let cal = try PostureAnalyzer.calibrate(joints: result.joints)
                print("\nCalibration would succeed:")
                print("  Side: \(cal.side)")
                print("  Metrics: \(cal.availableMetrics.joined(separator: ", "))")
                print("  Neck angle: \(String(format: "%.1f", cal.baselineNeckAngle))°")
                print("  Head-shoulder ratio: \(String(format: "%.3f", cal.baselineHeadShoulderRatio))")
                print("  Forward offset: \(String(format: "%.3f", cal.baselineForwardOffset))")
                if let drop = cal.baselineShoulderDrop {
                    print("  Shoulder drop: \(String(format: "%.3f", drop))")
                }
                report["calibrationWouldSucceed"] = true
                report["calibrationSide"] = cal.side
                report["calibrationMetrics"] = cal.availableMetrics
            } catch {
                print("\nCalibration would fail: \(error)")
                report["calibrationWouldSucceed"] = false
                report["calibrationError"] = "\(error)"
            }
        } else {
            print("No pose detected. Tips:")
            print("  - Ensure adequate lighting")
            print("  - Position yourself so head and shoulders are visible")
            print("  - Try moving closer to or further from the camera")
        }

        // Write JSON report
        let jsonFile = Config.logsDirectory.appendingPathComponent("diagnose_\(timestamp).json")
        if let jsonData = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: jsonFile)
            print("\nSaved report: \(jsonFile.path)")
        }

        print("Logs dir: \(Config.logsDirectory.path)")
    } catch {
        print("Error: \(error)")
    }
}

func calibrate(config: Config) async {
    print("Posture Calibration")
    print("====================")
    print()
    print("Sit in your best upright posture with your side facing the camera.")
    print("We'll take 3 snapshots over 6 seconds and average them.")
    print()
    print("Starting in 3 seconds...")

    do {
        try await Task.sleep(for: .seconds(3))
    } catch { return }

    struct Snapshot {
        let neckAngle: Double
        let headShoulderRatio: Double
        let forwardOffset: Double
        let shoulderDrop: Double?
        let metrics: [String]
        let side: String
    }

    var snapshots: [Snapshot] = []

    for i in 1...3 {
        print("  Capturing snapshot \(i)/3...")
        do {
            let camera = CameraCapture()
            let sampleBuffer = try await camera.captureFrame(deviceID: config.deviceID)
            let joints = try PoseDetector.detectPose(from: sampleBuffer)
            let cal = try PostureAnalyzer.calibrate(joints: joints)
            snapshots.append(Snapshot(
                neckAngle: cal.baselineNeckAngle,
                headShoulderRatio: cal.baselineHeadShoulderRatio,
                forwardOffset: cal.baselineForwardOffset,
                shoulderDrop: cal.baselineShoulderDrop,
                metrics: cal.availableMetrics,
                side: cal.side
            ))

            if config.verbose {
                print("    Neck angle: \(String(format: "%.1f", cal.baselineNeckAngle))°, "
                    + "Head ratio: \(String(format: "%.3f", cal.baselineHeadShoulderRatio)), "
                    + "Forward: \(String(format: "%.3f", cal.baselineForwardOffset)), "
                    + "Side: \(cal.side), Metrics: \(cal.availableMetrics.joined(separator: ", "))")
            }

            if i < 3 {
                try await Task.sleep(for: .seconds(2))
            }
        } catch {
            print("  Error on snapshot \(i): \(error)")
            print("  Retrying...")
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }

    guard !snapshots.isEmpty else {
        print("\nCalibration failed: Could not capture any valid poses.")
        print("Run 'StraightenUp diagnose' to check what the camera can see.")
        return
    }

    let count = Double(snapshots.count)
    let avgNeckAngle = snapshots.map(\.neckAngle).reduce(0, +) / count
    let avgHeadRatio = snapshots.map(\.headShoulderRatio).reduce(0, +) / count
    let avgForward = snapshots.map(\.forwardOffset).reduce(0, +) / count

    let dropsWithValues = snapshots.compactMap(\.shoulderDrop)
    let avgDrop: Double? = dropsWithValues.isEmpty ? nil : dropsWithValues.reduce(0, +) / Double(dropsWithValues.count)

    // Use the union of all metrics seen across snapshots
    let allMetrics = Array(Set(snapshots.flatMap(\.metrics))).sorted()
    let detectedSide = snapshots.last!.side

    guard allMetrics.count >= 2 else {
        print("\nCalibration failed: Only \(allMetrics.count) metric(s) computable (\(allMetrics.joined(separator: ", "))). Need at least 2.")
        print("Run 'StraightenUp diagnose' to check joint visibility.")
        return
    }

    let calibration = CalibrationData(
        timestamp: Date(),
        side: detectedSide,
        baselineNeckAngle: avgNeckAngle,
        baselineHeadShoulderRatio: avgHeadRatio,
        baselineForwardOffset: avgForward,
        baselineShoulderDrop: avgDrop,
        availableMetrics: allMetrics
    )

    do {
        try Config.saveCalibration(calibration)
        print()
        print("Calibration saved!")
        print("  Side: \(detectedSide)")
        print("  Metrics: \(allMetrics.joined(separator: ", "))")
        print("  Baseline neck angle: \(String(format: "%.1f", avgNeckAngle))°")
        print("  Baseline head-shoulder ratio: \(String(format: "%.3f", avgHeadRatio))")
        print("  Baseline forward offset: \(String(format: "%.3f", avgForward))")
        if let drop = avgDrop {
            print("  Baseline shoulder drop: \(String(format: "%.3f", drop))")
        }
        print("  Saved to: \(Config.calibrationFile.path)")
        print()
        print("You can now run 'StraightenUp monitor' to start monitoring.")
    } catch {
        print("\nFailed to save calibration: \(error)")
    }
}

switch command {
case "list-cameras":
    listCameras()
case "status":
    showStatus()
case "diagnose":
    await diagnose(config: config)
case "calibrate":
    await calibrate(config: config)
case "monitor":
    await Monitor.start(config: config)
case "help", "--help", "-h":
    printUsage()
default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}

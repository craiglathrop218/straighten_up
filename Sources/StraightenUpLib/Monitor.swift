import Foundation

public struct Monitor {
    public static func start(config: Config) async {
        guard let calibration = Config.loadCalibration() else {
            print("Error: \(StraightenUpError.notCalibrated)")
            return
        }

        var alertManager = AlertManager(cooldown: config.cooldown)
        var consecutiveBadCount = 0
        var wasAlerting = false

        print("Starting posture monitoring...")
        print("  Interval: \(config.interval)s")
        print("  Alert threshold: \(config.threshold) consecutive bad readings")
        print("  Cooldown: \(config.cooldown)s between alerts")
        print("  Calibrated side: \(calibration.side)")
        print("  Metrics: \(calibration.availableMetrics.joined(separator: ", "))")
        print("  Press Ctrl+C to stop.\n")

        setupSignalHandler()

        while !Task.isCancelled {
            do {
                let camera = CameraCapture()
                let sampleBuffer = try await camera.captureFrame(deviceID: config.deviceID)
                let joints = try PoseDetector.detectPose(from: sampleBuffer)
                let assessment = PostureAnalyzer.assess(
                    joints: joints,
                    calibration: calibration,
                    config: config
                )

                if config.verbose {
                    let timestamp = DateFormatter.localizedString(
                        from: Date(), dateStyle: .none, timeStyle: .medium
                    )
                    print("[\(timestamp)] \(assessment.details)")
                }

                if assessment.isGoodPosture {
                    if consecutiveBadCount > 0 && config.verbose {
                        print("  Posture improved! Resetting counter.")
                    }
                    consecutiveBadCount = 0
                    if wasAlerting {
                        wasAlerting = false
                        alertManager.resetCooldown()
                        if config.verbose {
                            print("  Alert cooldown reset.")
                        }
                    }
                } else {
                    consecutiveBadCount += 1
                    if config.verbose {
                        print("  Bad posture count: \(consecutiveBadCount)/\(config.threshold)")
                    }

                    if consecutiveBadCount >= config.threshold && alertManager.shouldAlert() {
                        AlertManager.sendNotification(
                            title: "Straighten Up!",
                            message: "You've been slouching. Sit up straight!"
                        )
                        AlertManager.playSound(name: config.sound)
                        alertManager.recordAlert()
                        wasAlerting = true

                        if config.verbose {
                            print("  ALERT sent!")
                        }
                    }
                }
            } catch {
                if config.verbose {
                    let timestamp = DateFormatter.localizedString(
                        from: Date(), dateStyle: .none, timeStyle: .medium
                    )
                    print("[\(timestamp)] Skipped: \(error)")
                }
            }

            do {
                try await Task.sleep(for: .seconds(config.interval))
            } catch {
                break
            }
        }

        print("\nMonitoring stopped.")
    }

    private static func setupSignalHandler() {
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler {
            print("\nReceived interrupt signal. Shutting down...")
            exit(0)
        }
        source.resume()
        signal(SIGINT, SIG_IGN)
    }
}

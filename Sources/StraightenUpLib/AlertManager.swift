import Foundation

public struct AlertManager {
    private var lastAlertTime: Date?
    private let cooldown: TimeInterval

    public init(cooldown: Int) {
        self.cooldown = TimeInterval(cooldown)
    }

    public mutating func shouldAlert() -> Bool {
        guard let lastAlert = lastAlertTime else { return true }
        return Date().timeIntervalSince(lastAlert) >= cooldown
    }

    public mutating func recordAlert() {
        lastAlertTime = Date()
    }

    public mutating func resetCooldown() {
        lastAlertTime = nil
    }

    public static func sendNotification(title: String, message: String) {
        let script = """
        display notification "\(escapeForAppleScript(message))" \
        with title "\(escapeForAppleScript(title))"
        """
        runOsascript(script)
    }

    public static func playSound(name: String) {
        let soundPath = "/System/Library/Sounds/\(name).aiff"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [soundPath]
        try? process.run()
    }

    private static func escapeForAppleScript(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runOsascript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
}

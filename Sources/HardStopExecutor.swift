import Foundation

final class HardStopExecutor {
    private var hasExecutedForCurrentIncident = false

    func executeIfConfigured(reason: String, settings: GuardrailSettings) -> Bool {
        guard !hasExecutedForCurrentIncident else { return false }
        hasExecutedForCurrentIncident = true

        writeLockFile(reason: reason, settings: settings)

        let command = settings.hardStopCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return true }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        try? process.run()
        return true
    }

    func reset() {
        hasExecutedForCurrentIncident = false
    }

    private func writeLockFile(reason: String, settings: GuardrailSettings) {
        let expandedPath = NSString(string: settings.hardStopLockFilePath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = [
            "reason": reason,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

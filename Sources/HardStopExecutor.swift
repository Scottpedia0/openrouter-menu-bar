import Foundation

final class HardStopExecutor {
    private var hasExecutedForCurrentIncident = false
    private let disallowedShellCharacters = CharacterSet(charactersIn: "&;|><`$\n\r")

    func executeIfConfigured(reason: String, settings: GuardrailSettings) -> Bool {
        guard !hasExecutedForCurrentIncident else { return false }
        hasExecutedForCurrentIncident = true

        writeLockFile(reason: reason, settings: settings)

        let command = settings.hardStopCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return true }
        guard command.rangeOfCharacter(from: disallowedShellCharacters) == nil else { return false }
        guard let invocation = parseInvocation(command) else { return false }

        let process = Process()
        if invocation.executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: invocation.executable)
            process.arguments = invocation.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [invocation.executable] + invocation.arguments
        }
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    func reset() {
        hasExecutedForCurrentIncident = false
    }

    private func writeLockFile(reason: String, settings: GuardrailSettings) {
        let expandedPath = NSString(string: settings.hardStopLockFilePath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        let standardizedPath = url.standardizedFileURL.path
        guard standardizedPath.hasPrefix(NSHomeDirectory()) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = [
            "reason": reason,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            do {
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                RuntimeLogger.shared.error("Failed to persist hard-stop lock file", error: error, metadata: ["path": url.path])
            }
        }
    }

    private func parseInvocation(_ command: String) -> (executable: String, arguments: [String])? {
        var tokens: [String] = []
        var current = ""
        var quoteCharacter: Character?

        for character in command {
            if let activeQuote = quoteCharacter {
                if character == activeQuote {
                    quoteCharacter = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quoteCharacter = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        guard quoteCharacter == nil else { return nil }
        if !current.isEmpty {
            tokens.append(current)
        }

        guard let executable = tokens.first else { return nil }
        return (executable, Array(tokens.dropFirst()))
    }
}

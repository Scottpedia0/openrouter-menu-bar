import Foundation

final class RuntimeLogger {
    static let shared = RuntimeLogger()

    let logFileURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "OpenRouterMenuBar.RuntimeLogger")
    private let encoder = JSONEncoder()
    private let isoFormatter = ISO8601DateFormatter()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("OpenRouterMenuBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        logFileURL = directory.appendingPathComponent("runtime.log")
        encoder.outputFormatting = [.sortedKeys]
    }

    func info(_ message: String, metadata: [String: String] = [:]) {
        write(level: "INFO", message: message, metadata: metadata)
    }

    func error(_ message: String, error: Error? = nil, metadata: [String: String] = [:]) {
        var merged = metadata
        if let error {
            merged["error"] = String(describing: error)
        }
        write(level: "ERROR", message: message, metadata: merged)
    }

    private func write(level: String, message: String, metadata: [String: String]) {
        queue.async {
            let timestamp = self.isoFormatter.string(from: Date())
            var line = "[\(timestamp)] [\(level)] \(message)"
            if !metadata.isEmpty,
               let data = try? self.encoder.encode(metadata),
               let json = String(data: data, encoding: .utf8) {
                line += " \(json)"
            }
            line += "\n"

            if !self.fileManager.fileExists(atPath: self.logFileURL.path) {
                self.fileManager.createFile(atPath: self.logFileURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: self.logFileURL) else { return }
            defer { try? handle.close() }

            do {
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
            }
        }
    }
}

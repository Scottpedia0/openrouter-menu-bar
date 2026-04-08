import Foundation

final class SettingsStore: ObservableObject {
    @Published var settings: GuardrailSettings {
        didSet {
            save()
        }
    }

    let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("OpenRouterMenuBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("settings.json")
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if
            let data = try? Data(contentsOf: fileURL),
            let loaded = try? decoder.decode(GuardrailSettings.self, from: data)
        {
            let normalized = Self.normalizedSettings(from: loaded)
            settings = normalized
            if normalized != loaded {
                save()
            }
        } else {
            settings = .default
            save()
        }
    }

    private func save() {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func suppressAlerts(for duration: TimeInterval, now: Date = Date()) {
        settings.alertSuppressedUntil = now.addingTimeInterval(duration)
    }

    func clearAlertSuppression() {
        settings.alertSuppressedUntil = nil
    }

    private static func normalizedSettings(from loaded: GuardrailSettings) -> GuardrailSettings {
        guard loaded.scopeKind != .all else { return loaded }

        guard let scopeIdentifier = loaded.scopeIdentifier, !scopeIdentifier.isEmpty else {
            var normalized = loaded
            normalized.scopeKind = .all
            normalized.scopeIdentifier = nil
            normalized.scopeLabel = nil
            return normalized
        }

        return loaded
    }
}

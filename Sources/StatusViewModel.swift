import Foundation

final class StatusViewModel: ObservableObject {
    @Published var snapshots: [SpendSnapshot] = []
    @Published var posture: ThresholdPosture = .normal
    @Published var warningReason: String?
    @Published var hasPendingAcknowledgement: Bool = false
    @Published var acknowledgementNote: String?
    @Published var alertOverrideNote: String?
    @Published var scopeDescription: String = "All OpenRouter"
    @Published var sourceDescription: String = "No data"
    @Published var lastUpdatedText: String = "Never"

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    init(settingsStore: SettingsStore, activityFeedStore: ActivityFeedStore) {}

    func update(from evaluation: GuardrailEngine.Evaluation, settings: GuardrailSettings, now: Date = Date()) {
        snapshots = evaluation.snapshots
        posture = evaluation.status.posture
        warningReason = evaluation.status.warningReason
        hasPendingAcknowledgement = evaluation.status.pendingAcknowledgement?.acknowledgedAt == nil
        acknowledgementNote = acknowledgementSummary(for: evaluation.status.pendingAcknowledgement)
        alertOverrideNote = alertOverrideSummary(until: settings.alertSuppressedUntil, now: now)
        scopeDescription = evaluation.scopeDescription
        sourceDescription = evaluation.sourceDescription
        lastUpdatedText = evaluation.lastUpdated.map(formatter.string(from:)) ?? "Never"
    }

    private func acknowledgementSummary(for pending: PendingAcknowledgement?) -> String? {
        guard let pending, pending.acknowledgedAt != nil else { return nil }

        switch pending.acknowledgeMode {
        case .fifteenMinutes, .oneHour:
            if let remindAgainAt = pending.remindAgainAt {
                return "Alerts muted until \(timeFormatter.string(from: remindAgainAt))."
            }
        case .untilGreen:
            return "Alerts muted until the app returns to green."
        case .none:
            break
        }

        return nil
    }

    private func alertOverrideSummary(until: Date?, now: Date) -> String? {
        guard let until, until > now else { return nil }
        return "Temporary override active until \(timeFormatter.string(from: until))."
    }
}

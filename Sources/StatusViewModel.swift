import Foundation

final class StatusViewModel: ObservableObject {
    @Published var snapshots: [SpendSnapshot] = []
    @Published var posture: ThresholdPosture = .normal
    @Published var warningReason: String?
    @Published var hasPendingAcknowledgement: Bool = false
    @Published var acknowledgementNote: String?
    @Published var alertOverrideNote: String?
    @Published var freshnessNote: String?
    @Published var isDataStale: Bool = false
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

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
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
        let freshness = freshnessSummary(lastUpdated: evaluation.lastUpdated, pollIntervalSeconds: settings.pollingIntervalSeconds, now: now)
        freshnessNote = freshness.note
        isDataStale = freshness.isStale
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

    private func freshnessSummary(lastUpdated: Date?, pollIntervalSeconds: Double, now: Date) -> (note: String?, isStale: Bool) {
        guard let lastUpdated else {
            return ("Waiting for the collector to write activity-feed.json.", true)
        }

        let staleAfter = max(pollIntervalSeconds * 2.5, 600)
        let age = now.timeIntervalSince(lastUpdated)
        guard age > staleAfter else {
            return (nil, false)
        }

        let relative = relativeFormatter.localizedString(for: lastUpdated, relativeTo: now)
        return ("Data may be stale. Last collector update was \(relative).", true)
    }
}

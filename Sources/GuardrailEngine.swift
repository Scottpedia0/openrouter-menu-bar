import Cocoa
import Foundation

final class GuardrailEngine {
    struct Evaluation {
        let snapshots: [SpendSnapshot]
        let status: GuardrailStatus
        let sourceDescription: String
        let lastUpdated: Date?
        let scopeDescription: String
    }

    private struct ResolvedFeed {
        let samples: [ActivitySample]
        let directSnapshots: [String: Double]
        let sourceDescription: String
        let lastUpdated: Date?
        let scopeDescription: String
    }

    private let settingsStore: SettingsStore
    private let activityFeedStore: ActivityFeedStore
    private let hardStopExecutor: HardStopExecutor
    private var pendingAcknowledgement: PendingAcknowledgement?

    init(
        settingsStore: SettingsStore,
        activityFeedStore: ActivityFeedStore,
        hardStopExecutor: HardStopExecutor
    ) {
        self.settingsStore = settingsStore
        self.activityFeedStore = activityFeedStore
        self.hardStopExecutor = hardStopExecutor
    }

    func evaluate(now: Date = Date()) -> Evaluation {
        let settings = settingsStore.settings
        let feed = activityFeedStore.load()
        let resolvedFeed = resolveFeedScope(feed: feed, settings: settings)
        let samples = resolvedFeed.samples
        let directSnapshots = resolvedFeed.directSnapshots
        let snapshots = SpendWindow.allCases.map { window in
            if let directAmount = directSnapshots[window.rawValue] {
                return SpendSnapshot(window: window, amount: Decimal(directAmount))
            }
            return SpendSnapshot(window: window, amount: decimalAmount(for: window, samples: samples, now: now))
        }

        let status = evaluateStatus(snapshots: snapshots, now: now)
        return Evaluation(
            snapshots: snapshots,
            status: status,
            sourceDescription: resolvedFeed.sourceDescription,
            lastUpdated: resolvedFeed.lastUpdated,
            scopeDescription: resolvedFeed.scopeDescription
        )
    }

    func acknowledgeWarning(mode: AlertAcknowledgeMode, now: Date = Date()) {
        guard let pending = pendingAcknowledgement else { return }
        pendingAcknowledgement = PendingAcknowledgement(
            startedAt: pending.startedAt,
            baselineAmount: pending.baselineAmount,
            triggerWindow: pending.triggerWindow,
            reason: pending.reason,
            requiredPosture: pending.requiredPosture,
            acknowledgedAt: now,
            acknowledgeMode: mode,
            remindAgainAt: mode.reminderInterval.map { now.addingTimeInterval($0) }
        )
    }

    func clearAcknowledgement() {
        pendingAcknowledgement = nil
    }

    private func evaluateStatus(snapshots: [SpendSnapshot], now: Date) -> GuardrailStatus {
        let settings = settingsStore.settings
        let hourSpend = doubleAmount(for: .hour, snapshots: snapshots)
        let daySpend = doubleAmount(for: .day, snapshots: snapshots)
        let weekSpend = doubleAmount(for: .week, snapshots: snapshots)
        let monthSpend = doubleAmount(for: .month, snapshots: snapshots)
        let unattended = isSystemUnattended(idleThresholdMinutes: settings.unattendedIdleMinutes)
        let unattendedSpend = unattended ? hourSpend : 0
        let isZeroActivity = hourSpend == 0 && daySpend == 0 && weekSpend == 0 && monthSpend == 0

        let warningOffset = max(0, settings.hourlyWarningPercentOverBaseline) / 100.0
        let dangerOffset = max(warningOffset, max(0, settings.hourlyDangerPercentOverBaseline) / 100.0)
        let hourlyBaseline = settings.hourlyBaselineThreshold
        let hasHourlyWindowThresholds = hourlyBaseline > 0
        let hourlyWarningThreshold = hourlyBaseline * (1 + warningOffset)
        let hourlyDangerThreshold = hourlyBaseline * (1 + dangerOffset)
        let hardStopThreshold = settings.hourlyHardStopThreshold
        let isHourlyWarning = hasHourlyWindowThresholds && hourSpend >= hourlyWarningThreshold
        let isHourlyDanger = hasHourlyWindowThresholds && hourSpend >= hourlyDangerThreshold
        let isHourlyHardStop = settings.hardStopEnabled && hardStopThreshold > 0 && hourSpend >= hardStopThreshold
        let isGuardrailOverrideActive = settings.alertSuppressedUntil.map { $0 > now } ?? false

        var posture: ThresholdPosture = .normal
        var reason: String?
        var triggeredWindow: SpendWindow = .hour
        var triggeredAmount = hourSpend

        if isZeroActivity {
            posture = .idle
        } else if isHourlyHardStop {
            posture = .danger
            reason = "Hourly hard kill cap crossed"
            triggeredWindow = .hour
            triggeredAmount = hourSpend
        } else if isHourlyDanger || daySpend >= settings.dailyHardStopThreshold {
            posture = .danger
            reason = isHourlyDanger ? "Hourly danger threshold crossed" : "Daily danger threshold crossed"
            triggeredWindow = hourSpend >= hourlyDangerThreshold ? .hour : .day
            triggeredAmount = hourSpend >= hourlyDangerThreshold ? hourSpend : daySpend
        } else if unattended && unattendedSpend >= settings.unattendedHardStopThreshold {
            posture = .danger
            reason = "Unattended danger threshold crossed"
            triggeredWindow = .hour
            triggeredAmount = hourSpend
        } else if isHourlyWarning || daySpend >= settings.dailyWarningThreshold {
            posture = .warning
            reason = isHourlyWarning ? "Hourly warning threshold crossed" : "Daily warning crossed"
            triggeredWindow = hourSpend >= hourlyWarningThreshold ? .hour : .day
            triggeredAmount = isHourlyWarning ? hourSpend : daySpend
        } else if unattended && unattendedSpend >= settings.unattendedWarningThreshold {
            posture = .warning
            reason = "Unattended warning crossed"
            triggeredWindow = .hour
            triggeredAmount = hourSpend
        }

        if posture == .normal {
            pendingAcknowledgement = nil
        } else if posture == .idle {
            if !shouldCarryAcknowledgementThroughIdle(pendingAcknowledgement) {
                pendingAcknowledgement = nil
            }
        } else {
            let incidentReason = reason ?? posture.rawValue.capitalized
            if let pending = pendingAcknowledgement {
                if shouldStartNewIncident(from: pending, posture: posture, now: now) {
                    pendingAcknowledgement = PendingAcknowledgement(
                        startedAt: now,
                        baselineAmount: triggeredAmount,
                        triggerWindow: triggeredWindow,
                        reason: incidentReason,
                        requiredPosture: posture,
                        acknowledgedAt: nil,
                        acknowledgeMode: nil,
                        remindAgainAt: nil
                    )
                }
            } else {
                pendingAcknowledgement = PendingAcknowledgement(
                    startedAt: now,
                    baselineAmount: triggeredAmount,
                    triggerWindow: triggeredWindow,
                    reason: incidentReason,
                    requiredPosture: posture,
                    acknowledgedAt: nil,
                    acknowledgeMode: nil,
                    remindAgainAt: nil
                )
            }
        }

        if isHourlyHardStop && !isGuardrailOverrideActive {
            _ = hardStopExecutor.executeIfConfigured(reason: reason ?? "Hourly hard kill cap crossed", settings: settings)
        } else {
            hardStopExecutor.reset()
        }

        return GuardrailStatus(posture: posture, warningReason: reason, pendingAcknowledgement: pendingAcknowledgement)
    }

    private func decimalAmount(for window: SpendWindow, samples: [ActivitySample], now: Date) -> Decimal {
        Decimal(doubleAmount(for: window, samples: samples, now: now))
    }

    private func doubleAmount(for window: SpendWindow, samples: [ActivitySample], now: Date) -> Double {
        let calendar = Calendar.current
        let startDate: Date
        switch window {
        case .hour:
            startDate = now.addingTimeInterval(-3600)
        case .day:
            startDate = calendar.startOfDay(for: now)
        case .week:
            startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .month:
            startDate = calendar.dateInterval(of: .month, for: now)?.start ?? now
        }

        return samples
            .filter { $0.timestamp >= startDate && $0.timestamp <= now }
            .reduce(0) { $0 + $1.amount }
    }

    private func doubleAmount(for window: SpendWindow, snapshots: [SpendSnapshot]) -> Double {
        snapshots.first(where: { $0.window == window }).map { NSDecimalNumber(decimal: $0.amount).doubleValue } ?? 0
    }

    private func shouldStartNewIncident(from pending: PendingAcknowledgement, posture: ThresholdPosture, now: Date) -> Bool {
        if posture == .danger && pending.requiredPosture != .danger {
            return true
        }

        guard pending.acknowledgedAt != nil else {
            return false
        }

        if pending.acknowledgeMode == .untilGreen {
            return false
        }

        if let remindAgainAt = pending.remindAgainAt, now >= remindAgainAt {
            return true
        }

        return false
    }

    private func shouldCarryAcknowledgementThroughIdle(_ pending: PendingAcknowledgement?) -> Bool {
        guard let pending else { return false }
        return pending.acknowledgedAt != nil && pending.acknowledgeMode == .untilGreen
    }

    private func resolveFeedScope(feed: ActivityFeed?, settings: GuardrailSettings) -> ResolvedFeed {
        let fallback = ResolvedFeed(
            samples: feed?.samples ?? [],
            directSnapshots: feed?.directSnapshots ?? [:],
            sourceDescription: feed?.sourceDescription ?? "No activity feed loaded yet",
            lastUpdated: feed?.fetchedAt,
            scopeDescription: "All OpenRouter"
        )

        guard settings.scopeKind != .all else {
            return fallback
        }

        guard
            let scopeIdentifier = settings.scopeIdentifier,
            !scopeIdentifier.isEmpty
        else {
            return fallback
        }

        let scoped = feed?.scopes?.first(where: { scope in
            scope.kind == settings.scopeKind && scope.key == scopeIdentifier
        })

        guard let scoped else {
            return fallback
        }

        return ResolvedFeed(
            samples: scoped.samples ?? [],
            directSnapshots: scoped.directSnapshots ?? [:],
            sourceDescription: scoped.sourceDescription ?? fallback.sourceDescription,
            lastUpdated: scoped.fetchedAt ?? fallback.lastUpdated,
            scopeDescription: scoped.label
        )
    }

    private func isSystemUnattended(idleThresholdMinutes: Double) -> Bool {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        return idleSeconds >= idleThresholdMinutes * 60
    }
}

import Foundation

enum SpendWindow: String, CaseIterable, Identifiable {
    case hour
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: return "Last hour"
        case .day: return "1 day"
        case .week: return "1 week"
        case .month: return "1 month"
        }
    }
}

enum GuardrailScopeKind: String, Codable, CaseIterable, Identifiable {
    case all
    case app
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All OpenRouter"
        case .app:
            return "One app"
        case .user:
            return "One user/run"
        }
    }
}

enum ThresholdPosture: String {
    case normal
    case idle
    case warning
    case danger
}

enum AlertAcknowledgeMode: String, CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case untilGreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes:
            return "15m"
        case .oneHour:
            return "1h"
        case .untilGreen:
            return "Until green"
        }
    }

    var reminderInterval: TimeInterval? {
        switch self {
        case .fifteenMinutes:
            return 15 * 60
        case .oneHour:
            return 60 * 60
        case .untilGreen:
            return nil
        }
    }
}

struct SpendSnapshot: Equatable {
    let window: SpendWindow
    let amount: Decimal
}

struct GuardrailSettings: Codable, Equatable {
    var openRouterActivityURL: String
    var scopeKind: GuardrailScopeKind
    var scopeIdentifier: String?
    var scopeLabel: String?
    var hourlyWarningThreshold: Double
    var hourlyHardStopThreshold: Double
    var hourlyBaselineThreshold: Double
    var hourlyWarningPercentOverBaseline: Double
    var hourlyDangerPercentOverBaseline: Double
    var dailyWarningThreshold: Double
    var dailyHardStopThreshold: Double
    var unattendedWarningThreshold: Double
    var unattendedHardStopThreshold: Double
    var unattendedIdleMinutes: Double
    var escalationPercentageAfterWarning: Double
    var hardStopEnabled: Bool
    var hardStopCommand: String
    var hardStopLockFilePath: String
    var pollingIntervalSeconds: Double
    var alertSuppressedUntil: Date?

    static let `default` = GuardrailSettings(
        openRouterActivityURL: "https://openrouter.ai/activity",
        scopeKind: .all,
        scopeIdentifier: nil,
        scopeLabel: nil,
        hourlyWarningThreshold: 15,
        hourlyHardStopThreshold: 30,
        hourlyBaselineThreshold: 15,
        hourlyWarningPercentOverBaseline: 50,
        hourlyDangerPercentOverBaseline: 300,
        dailyWarningThreshold: 100,
        dailyHardStopThreshold: 180,
        unattendedWarningThreshold: 25,
        unattendedHardStopThreshold: 40,
        unattendedIdleMinutes: 20,
        escalationPercentageAfterWarning: 25,
        hardStopEnabled: false,
        hardStopCommand: "",
        hardStopLockFilePath: "~/Library/Application Support/OpenRouterMenuBar/hard-stop.lock",
        pollingIntervalSeconds: 300,
        alertSuppressedUntil: nil
    )

    private enum CodingKeys: String, CodingKey {
        case openRouterActivityURL
        case scopeKind
        case scopeIdentifier
        case scopeLabel
        case hourlyWarningThreshold
        case hourlyHardStopThreshold
        case hourlyBaselineThreshold
        case hourlyWarningPercentOverBaseline
        case hourlyDangerPercentOverBaseline
        case dailyWarningThreshold
        case dailyHardStopThreshold
        case unattendedWarningThreshold
        case unattendedHardStopThreshold
        case unattendedIdleMinutes
        case escalationPercentageAfterWarning
        case hardStopEnabled
        case hardStopCommand
        case hardStopLockFilePath
        case pollingIntervalSeconds
        case alertSuppressedUntil
    }

    init(
        openRouterActivityURL: String,
        scopeKind: GuardrailScopeKind,
        scopeIdentifier: String?,
        scopeLabel: String?,
        hourlyWarningThreshold: Double,
        hourlyHardStopThreshold: Double,
        hourlyBaselineThreshold: Double,
        hourlyWarningPercentOverBaseline: Double,
        hourlyDangerPercentOverBaseline: Double,
        dailyWarningThreshold: Double,
        dailyHardStopThreshold: Double,
        unattendedWarningThreshold: Double,
        unattendedHardStopThreshold: Double,
        unattendedIdleMinutes: Double,
        escalationPercentageAfterWarning: Double,
        hardStopEnabled: Bool,
        hardStopCommand: String,
        hardStopLockFilePath: String,
        pollingIntervalSeconds: Double,
        alertSuppressedUntil: Date?
    ) {
        self.openRouterActivityURL = openRouterActivityURL
        self.scopeKind = scopeKind
        self.scopeIdentifier = scopeIdentifier
        self.scopeLabel = scopeLabel
        self.hourlyWarningThreshold = hourlyWarningThreshold
        self.hourlyHardStopThreshold = hourlyHardStopThreshold
        self.hourlyBaselineThreshold = hourlyBaselineThreshold
        self.hourlyWarningPercentOverBaseline = hourlyWarningPercentOverBaseline
        self.hourlyDangerPercentOverBaseline = hourlyDangerPercentOverBaseline
        self.dailyWarningThreshold = dailyWarningThreshold
        self.dailyHardStopThreshold = dailyHardStopThreshold
        self.unattendedWarningThreshold = unattendedWarningThreshold
        self.unattendedHardStopThreshold = unattendedHardStopThreshold
        self.unattendedIdleMinutes = unattendedIdleMinutes
        self.escalationPercentageAfterWarning = escalationPercentageAfterWarning
        self.hardStopEnabled = hardStopEnabled
        self.hardStopCommand = hardStopCommand
        self.hardStopLockFilePath = hardStopLockFilePath
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.alertSuppressedUntil = alertSuppressedUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decoderHourlyWarningThreshold = (try container.decodeIfPresent(Double.self, forKey: .hourlyWarningThreshold)) ?? Self.default.hourlyWarningThreshold
        let decoderHourlyHardStopThreshold = (try container.decodeIfPresent(Double.self, forKey: .hourlyHardStopThreshold)) ?? Self.default.hourlyHardStopThreshold
        let decoderHourlyBaselineThreshold = (try container.decodeIfPresent(Double.self, forKey: .hourlyBaselineThreshold)) ?? decoderHourlyWarningThreshold

        let warningPercentPresent = container.contains(.hourlyWarningPercentOverBaseline)
        let dangerPercentPresent = container.contains(.hourlyDangerPercentOverBaseline)
        var warningPercent = (try container.decodeIfPresent(Double.self, forKey: .hourlyWarningPercentOverBaseline)) ?? Self.default.hourlyWarningPercentOverBaseline
        var dangerPercent = (try container.decodeIfPresent(Double.self, forKey: .hourlyDangerPercentOverBaseline)) ?? Self.default.hourlyDangerPercentOverBaseline

        let hasLegacyHourlyPair = container.contains(.hourlyWarningThreshold) && container.contains(.hourlyHardStopThreshold)

        if !warningPercentPresent {
            if hasLegacyHourlyPair && decoderHourlyBaselineThreshold > 0 {
                warningPercent = 0
            } else {
                warningPercent = Self.default.hourlyWarningPercentOverBaseline
            }
        }

        if !dangerPercentPresent {
            let inferredDangerPercent = (decoderHourlyBaselineThreshold > 0 && decoderHourlyHardStopThreshold > 0)
                ? ((decoderHourlyHardStopThreshold / decoderHourlyBaselineThreshold) - 1.0) * 100.0 as Double
                : Self.default.hourlyDangerPercentOverBaseline
            dangerPercent = inferredDangerPercent.isFinite && inferredDangerPercent > 0
                ? inferredDangerPercent
                : Self.default.hourlyDangerPercentOverBaseline
        }

        if dangerPercent < warningPercent {
            dangerPercent = warningPercent
        }

        self.init(
            openRouterActivityURL: (try container.decodeIfPresent(String.self, forKey: .openRouterActivityURL)) ?? Self.default.openRouterActivityURL,
            scopeKind: (try container.decodeIfPresent(GuardrailScopeKind.self, forKey: .scopeKind)) ?? Self.default.scopeKind,
            scopeIdentifier: try container.decodeIfPresent(String.self, forKey: .scopeIdentifier),
            scopeLabel: try container.decodeIfPresent(String.self, forKey: .scopeLabel),
            hourlyWarningThreshold: decoderHourlyWarningThreshold,
            hourlyHardStopThreshold: decoderHourlyHardStopThreshold,
            hourlyBaselineThreshold: decoderHourlyBaselineThreshold,
            hourlyWarningPercentOverBaseline: max(0, warningPercent),
            hourlyDangerPercentOverBaseline: max(warningPercent, dangerPercent),
            dailyWarningThreshold: (try container.decodeIfPresent(Double.self, forKey: .dailyWarningThreshold)) ?? Self.default.dailyWarningThreshold,
            dailyHardStopThreshold: (try container.decodeIfPresent(Double.self, forKey: .dailyHardStopThreshold)) ?? Self.default.dailyHardStopThreshold,
            unattendedWarningThreshold: (try container.decodeIfPresent(Double.self, forKey: .unattendedWarningThreshold)) ?? Self.default.unattendedWarningThreshold,
            unattendedHardStopThreshold: (try container.decodeIfPresent(Double.self, forKey: .unattendedHardStopThreshold)) ?? Self.default.unattendedHardStopThreshold,
            unattendedIdleMinutes: (try container.decodeIfPresent(Double.self, forKey: .unattendedIdleMinutes)) ?? Self.default.unattendedIdleMinutes,
            escalationPercentageAfterWarning: (try container.decodeIfPresent(Double.self, forKey: .escalationPercentageAfterWarning)) ?? Self.default.escalationPercentageAfterWarning,
            hardStopEnabled: (try container.decodeIfPresent(Bool.self, forKey: .hardStopEnabled)) ?? Self.default.hardStopEnabled,
            hardStopCommand: (try container.decodeIfPresent(String.self, forKey: .hardStopCommand)) ?? Self.default.hardStopCommand,
            hardStopLockFilePath: (try container.decodeIfPresent(String.self, forKey: .hardStopLockFilePath)) ?? Self.default.hardStopLockFilePath,
            pollingIntervalSeconds: (try container.decodeIfPresent(Double.self, forKey: .pollingIntervalSeconds)) ?? Self.default.pollingIntervalSeconds,
            alertSuppressedUntil: try container.decodeIfPresent(Date.self, forKey: .alertSuppressedUntil)
        )
    }
}

struct GuardrailStatus {
    let posture: ThresholdPosture
    let warningReason: String?
    let pendingAcknowledgement: PendingAcknowledgement?
}

struct PendingAcknowledgement {
    let startedAt: Date
    let baselineAmount: Double
    let triggerWindow: SpendWindow
    let reason: String
    let requiredPosture: ThresholdPosture
    let acknowledgedAt: Date?
    let acknowledgeMode: AlertAcknowledgeMode?
    let remindAgainAt: Date?
}

struct ActivitySample: Codable {
    let timestamp: Date
    let amount: Double
}

struct ActivityFeed: Codable {
    let samples: [ActivitySample]
    let sourceDescription: String
    let fetchedAt: Date
    let directSnapshots: [String: Double]?
    let scopes: [ActivityScopedFeed]?
}

struct ActivityScopedFeed: Codable, Identifiable {
    let kind: GuardrailScopeKind
    let key: String
    let label: String
    let sourceDescription: String?
    let fetchedAt: Date?
    let samples: [ActivitySample]?
    let directSnapshots: [String: Double]?

    var id: String { "\(kind.rawValue):\(key)" }
}

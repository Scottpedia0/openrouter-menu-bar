import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let activityFeedStore: ActivityFeedStore

    private let overrideFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let taggingHelpText = """
Best public setup: use one OpenRouter key per app, then let the collector read account-wide totals with a management key. App attribution headers still help OpenRouter Activity stay legible, and a stable user value helps break spend down by run when your feed includes user scopes.
"""

    var body: some View {
        Form {
            Section("OpenRouter") {
                TextField("Activity URL", text: binding(\.openRouterActivityURL))
                TextField("Poll every seconds", value: binding(\.pollingIntervalSeconds), format: .number)
            }

            Section("Spend scope") {
                Picker("View", selection: scopeKindBinding) {
                    ForEach(GuardrailScopeKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }

                switch settingsStore.settings.scopeKind {
                case .all:
                    Text("Default: watch all OpenRouter spend available in the current feed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .app:
                    if availableScopes(for: .app).isEmpty {
                        Text("No app scopes are available in the current feed yet. One app becomes real when the collector can see labeled per-app keys or another truthful app-level source.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("App", selection: scopeIdentifierBinding(for: .app)) {
                            ForEach(availableScopes(for: .app)) { scope in
                                Text(scope.label).tag(scope.key)
                            }
                        }
                    }
                case .user:
                    if availableScopes(for: .user).isEmpty {
                        Text("No tagged user/run scopes are available in the current feed yet. The app will keep falling back to All OpenRouter until scoped user data is present.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("User / run", selection: scopeIdentifierBinding(for: .user)) {
                            ForEach(availableScopes(for: .user)) { scope in
                                Text(scope.label).tag(scope.key)
                            }
                        }
                    }
                }
            }

            Section {
                Text("Best live setup: one OpenRouter key per app plus a management key for the collector. App attribution headers keep OpenRouter Activity legible, and stable user values help isolate a specific cloud run when your feed includes user scopes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("App attribution: per-app keys, plus `HTTP-Referer` + `X-OpenRouter-Title`")
                    .font(.footnote)
                Text("Per-run attribution: stable `user` value like `openwork:ses_123`")
                    .font(.footnote)
            } header: {
                HStack(spacing: 6) {
                    Text("Attribution & tagging")
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                        .help(taggingHelpText)
                }
            }

            Section("Warning / Danger") {
                currencyField("Hourly baseline", keyPath: \.hourlyBaselineThreshold)
                TextField("Hourly warning % over baseline", value: binding(\.hourlyWarningPercentOverBaseline), format: .number)
                TextField("Hourly danger % over baseline", value: binding(\.hourlyDangerPercentOverBaseline), format: .number)
                currencyField("Daily warning", keyPath: \.dailyWarningThreshold)
                currencyField("Daily danger", keyPath: \.dailyHardStopThreshold)
                Text("Last hour is a rolling 60-minute window. After you stop new spend, it can stay high or climb briefly while in-flight requests settle, then decay as older spend ages out.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Hard kill") {
                Text(hardKillStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    if settingsStore.settings.hardStopEnabled {
                        Button("Disable hard kill") {
                            settingsStore.settings.hardStopEnabled = false
                        }
                    } else {
                        Button("Arm hard kill") {
                            settingsStore.settings.hardStopEnabled = true
                        }
                    }
                }
                currencyField("Last hour hard kill cap", keyPath: \.hourlyHardStopThreshold)
                Text("Local fallback only. Do not depend on this. Set critical limits directly in OpenRouter. Crossing this cap writes the lock file and runs the optional shell command once, unless a temporary override is active.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Unattended") {
                currencyField("Unattended warning", keyPath: \.unattendedWarningThreshold)
                currencyField("Unattended danger", keyPath: \.unattendedHardStopThreshold)
                TextField("Idle minutes", value: binding(\.unattendedIdleMinutes), format: .number)
            }

            Section("Optional automation hook") {
                TextField("Shell command", text: binding(\.hardStopCommand), axis: .vertical)
                TextField("Lock file path", text: binding(\.hardStopLockFilePath))
            }

            Section("Temporary override") {
                Text(guardrailOverrideStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Quiet 20m") {
                        settingsStore.suppressAlerts(for: 20 * 60)
                    }
                    Button("Quiet 1d") {
                        settingsStore.suppressAlerts(for: 24 * 60 * 60)
                    }
                    Button("Resume now") {
                        settingsStore.clearAlertSuppression()
                    }
                }
            }

        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 480, height: 560)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<GuardrailSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private func currencyField(_ title: String, keyPath: WritableKeyPath<GuardrailSettings, Double>) -> some View {
        TextField(title, value: binding(keyPath), format: .currency(code: "USD"))
    }

    private var scopeKindBinding: Binding<GuardrailScopeKind> {
        Binding(
            get: { settingsStore.settings.scopeKind },
            set: { newKind in
                settingsStore.settings.scopeKind = newKind
                if newKind == .all {
                    settingsStore.settings.scopeIdentifier = nil
                    settingsStore.settings.scopeLabel = nil
                } else {
                    let first = availableScopes(for: newKind).first
                    settingsStore.settings.scopeIdentifier = first?.key
                    settingsStore.settings.scopeLabel = first?.label
                }
            }
        )
    }

    private func scopeIdentifierBinding(for kind: GuardrailScopeKind) -> Binding<String> {
        Binding(
            get: {
                if let current = settingsStore.settings.scopeIdentifier,
                   availableScopes(for: kind).contains(where: { $0.key == current }) {
                    return current
                }
                return availableScopes(for: kind).first?.key ?? ""
            },
            set: { newValue in
                settingsStore.settings.scopeIdentifier = newValue
                settingsStore.settings.scopeLabel = availableScopes(for: kind).first(where: { $0.key == newValue })?.label
            }
        )
    }

    private func availableScopes(for kind: GuardrailScopeKind) -> [ActivityScopedFeed] {
        (activityFeedStore.load()?.scopes ?? [])
            .filter { $0.kind == kind }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var guardrailOverrideStatus: String {
        guard let until = settingsStore.settings.alertSuppressedUntil, until > Date() else {
            return "No temporary override is active. Alerts and hard kill behave normally."
        }

        return "Beeps, notifications, and hard kill are paused until \(overrideFormatter.string(from: until)). Thresholds still update visually."
    }

    private var hardKillStatus: String {
        if settingsStore.settings.hardStopEnabled {
            return "Hard kill is armed. Local fallback only. Set critical limits directly in OpenRouter."
        }

        return "Hard kill is disabled. Local fallback only. Set critical limits directly in OpenRouter."
    }
}

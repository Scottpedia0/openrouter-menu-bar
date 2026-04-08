import SwiftUI

struct StatusPopoverView: View {
    @State private var isHourHelpVisible = false
    @ObservedObject var viewModel: StatusViewModel
    let onOpenSettings: () -> Void
    let onAcknowledgeWarning: (AlertAcknowledgeMode) -> Void

    private let hourWindowHelpText = "Last hour is the rolling 60-minute total. The 1 day, 1 week, and 1 month rows are meant to track the same filter-style windows you see in OpenRouter Activity. Last hour can keep rising briefly even after new usage slows or stops while in-flight requests settle. Need to stop a spike immediately? Open OpenRouter from the menu bar and disable the API key, or use Settings to arm hard kill."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenRouter Menu Bar")
                        .font(.headline)
                    Text(postureLabel)
                        .font(.subheadline)
                        .foregroundStyle(postureColor)
                    Text(viewModel.scopeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(postureColor)
                    .frame(width: 12, height: 12)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.snapshots, id: \.window.id) { snapshot in
                    HStack {
                        windowLabel(for: snapshot.window)
                        Spacer()
                        Text(currencyString(snapshot.amount))
                            .monospacedDigit()
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isHourHelpVisible {
                Text(hourWindowHelpText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let warningReason = viewModel.warningReason {
                Text(warningReason)
                    .font(.footnote)
                    .foregroundStyle(postureColor)
            }

            if viewModel.hasPendingAcknowledgement {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Acknowledge and remind again:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(AlertAcknowledgeMode.allCases) { mode in
                            Button(mode.title) {
                                onAcknowledgeWarning(mode)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text("Status stays visible. Repeated alerting pauses until the reminder window expires, or until the app returns to green.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let acknowledgementNote = viewModel.acknowledgementNote {
                Text(acknowledgementNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let alertOverrideNote = viewModel.alertOverrideNote {
                Text(alertOverrideNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text("Updated \(viewModel.lastUpdatedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var postureLabel: String {
        switch viewModel.posture {
        case .normal: return "Normal"
        case .idle: return "Idle"
        case .warning: return "Warning"
        case .danger: return "Danger"
        }
    }

    private var postureColor: Color {
        switch viewModel.posture {
        case .normal: return .green
        case .idle: return .gray
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private func currencyString(_ decimal: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "$0.00"
    }

    @ViewBuilder
    private func windowLabel(for window: SpendWindow) -> some View {
        if window == .hour {
            HStack(spacing: 4) {
                Text(window.title)
                Button {
                    isHourHelpVisible.toggle()
                } label: {
                    Image(systemName: isHourHelpVisible ? "questionmark.circle.fill" : "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(hourWindowHelpText)
            }
        } else {
            Text(window.title)
        }
    }
}

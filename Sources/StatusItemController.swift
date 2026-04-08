import AppKit
import Foundation
import SwiftUI

enum StatusItemControllerError: LocalizedError {
    case missingStatusButton

    var errorDescription: String? {
        switch self {
        case .missingStatusButton:
            return "The system status item button was not available."
        }
    }
}

final class StatusItemController {
    private let settingsStore = SettingsStore()
    private let activityFeedStore = ActivityFeedStore()
    private let hardStopExecutor = HardStopExecutor()
    private let runtimeLogger: RuntimeLogger
    private lazy var engine = GuardrailEngine(
        settingsStore: settingsStore,
        activityFeedStore: activityFeedStore,
        hardStopExecutor: hardStopExecutor
    )

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var timer: Timer?
    private let viewModel: StatusViewModel
    private var settingsWindowController: NSWindowController?
    private var lastPosture: ThresholdPosture?
    private var lastDangerNotificationAt: Date?

    init(runtimeLogger: RuntimeLogger) throws {
        self.runtimeLogger = runtimeLogger
        viewModel = StatusViewModel(settingsStore: settingsStore, activityFeedStore: activityFeedStore)
        try configureStatusItem()
        configurePopover()
        refresh()
        scheduleTimer()
    }

    deinit {
        timer?.invalidate()
    }

    private func configureStatusItem() throws {
        guard let button = statusItem.button else {
            runtimeLogger.error("Status item button unavailable during setup")
            throw StatusItemControllerError.missingStatusButton
        }

        button.target = self
        button.action = #selector(handlePrimaryClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.image = badgeImage(text: "$0", posture: .normal)
        button.toolTip = "OpenRouter Menu Bar"
        runtimeLogger.info("Status item configured")
    }

    private func configurePopover() {
        popover.contentSize = NSSize(width: 360, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: StatusPopoverView(viewModel: viewModel, onOpenSettings: { [weak self] in
            self?.showSettingsWindow()
        }, onAcknowledgeWarning: { [weak self] mode in
            self?.acknowledgeCurrentWarning(mode: mode)
        }))
    }

    private func scheduleTimer() {
        let interval = max(settingsStore.settings.pollingIntervalSeconds, 5)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        runtimeLogger.info("Refresh timer scheduled", metadata: ["intervalSeconds": String(format: "%.0f", interval)])
    }

    private func refresh() {
        clearExpiredAlertSuppressionIfNeeded()
        let evaluation = engine.evaluate()
        viewModel.update(from: evaluation, settings: settingsStore.settings)
        updateStatusButton(using: evaluation)
        handleAlerting(using: evaluation)
        runtimeLogger.info(
            "Refreshed status item",
            metadata: [
                "posture": evaluation.status.posture.rawValue,
                "source": evaluation.sourceDescription,
                "hourSpend": String(format: "%.2f", evaluation.snapshots.first(where: { $0.window == .hour }).map { NSDecimalNumber(decimal: $0.amount).doubleValue } ?? 0)
            ]
        )
    }

    private func updateStatusButton(using evaluation: GuardrailEngine.Evaluation) {
        guard let button = statusItem.button else { return }
        let hourSpend = evaluation.snapshots.first(where: { $0.window == .hour }).map { NSDecimalNumber(decimal: $0.amount).doubleValue } ?? 0
        button.contentTintColor = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = badgeImage(text: String(format: "$%.0f", hourSpend), posture: evaluation.status.posture)
    }

    private func tintColor(for posture: ThresholdPosture) -> NSColor {
        switch posture {
        case .normal:
            return NSColor(calibratedRed: 0.24, green: 0.62, blue: 0.41, alpha: 1.0)
        case .idle:
            return NSColor(calibratedRed: 0.58, green: 0.58, blue: 0.59, alpha: 1.0)
        case .warning:
            return NSColor(calibratedRed: 0.76, green: 0.53, blue: 0.20, alpha: 1.0)
        case .danger:
            return NSColor(calibratedRed: 0.73, green: 0.27, blue: 0.25, alpha: 1.0)
        }
    }

    private func badgeImage(text: String, posture: ThresholdPosture) -> NSImage? {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attributedText = NSAttributedString(string: text, attributes: textAttributes)
        let textSize = attributedText.size()
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 3
        let badgeHeight = ceil(textSize.height + verticalPadding * 2)
        let badgeWidth = ceil(textSize.width + horizontalPadding * 2)
        let imageSize = NSSize(width: badgeWidth, height: badgeHeight)

        let image = NSImage(size: imageSize)
        image.lockFocus()

        let badgeRect = NSRect(origin: .zero, size: imageSize)
        let pillPath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2)
        tintColor(for: posture).setFill()
        pillPath.fill()

        let textOrigin = NSPoint(
            x: round((badgeWidth - textSize.width) / 2),
            y: round((badgeHeight - textSize.height) / 2) - 1
        )
        attributedText.draw(at: textOrigin)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func postNotification(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "display notification \(appleScriptString(body)) with title \(appleScriptString(title))"
        ]
        do {
            try process.run()
            runtimeLogger.info("Posted macOS notification", metadata: ["title": title, "body": body])
        } catch {
            runtimeLogger.error("Failed to post notification", metadata: ["error": error.localizedDescription])
        }
    }

    private func appleScriptString(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func handleAlerting(using evaluation: GuardrailEngine.Evaluation) {
        let posture = evaluation.status.posture
        let reason = evaluation.status.warningReason ?? "Threshold crossed"
        let needsAcknowledgement = evaluation.status.pendingAcknowledgement?.acknowledgedAt == nil
        let alertsSuppressed = settingsStore.settings.alertSuppressedUntil.map { $0 > Date() } ?? false

        if alertsSuppressed {
            lastDangerNotificationAt = nil
            lastPosture = posture
            return
        }

        if posture == .danger && needsAcknowledgement {
            runtimeLogger.info("Triggered danger alert", metadata: ["reason": reason])
            NSSound.beep()
            let now = Date()
            if lastDangerNotificationAt == nil || now.timeIntervalSince(lastDangerNotificationAt!) >= 300 {
                postNotification(title: "OpenRouter red alert", body: reason)
                lastDangerNotificationAt = now
            }
        } else if posture == .idle {
            lastDangerNotificationAt = nil
        } else if posture == .warning && lastPosture != .warning && needsAcknowledgement {
            runtimeLogger.info("Triggered warning alert", metadata: ["reason": reason])
            NSSound.beep()
            postNotification(title: "OpenRouter warning", body: reason)
            lastDangerNotificationAt = nil
        } else if posture == .normal {
            lastDangerNotificationAt = nil
        }
        lastPosture = posture
    }

    private func clearExpiredAlertSuppressionIfNeeded(now: Date = Date()) {
        guard let until = settingsStore.settings.alertSuppressedUntil, until <= now else { return }
        settingsStore.clearAlertSuppression()
    }

    @objc private func handlePrimaryClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            togglePopover()
            return
        }

        openActivityURL()
    }

    private func acknowledgeCurrentWarning(mode: AlertAcknowledgeMode) {
        engine.acknowledgeWarning(mode: mode)
        runtimeLogger.info("User acknowledged alert", metadata: ["mode": mode.rawValue])
        refresh()
    }

    private func openActivityURL() {
        let urlString = settingsStore.settings.openRouterActivityURL
        guard let url = URL(string: urlString) else {
            runtimeLogger.error("Configured activity URL is invalid", metadata: ["url": urlString])
            return
        }

        openURLInChrome(url)
    }

    private func openURLInChrome(_ url: URL) {
        guard let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            runtimeLogger.error("Google Chrome not found; falling back to system default browser")
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: chromeURL, configuration: configuration)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            let controller = NSWindowController(window: NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            ))
            controller.window?.title = "OpenRouter Menu Bar Settings"
            controller.window?.center()
            controller.window?.isReleasedWhenClosed = false
            controller.window?.contentView = NSHostingView(rootView: SettingsView(settingsStore: settingsStore, activityFeedStore: activityFeedStore))
            settingsWindowController = controller
        }

        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

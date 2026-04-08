import SwiftUI
import AppKit

@main
struct OpenRouterMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private let runtimeLogger = RuntimeLogger.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        runtimeLogger.info("Application did finish launching")
        NSApp.setActivationPolicy(.accessory)

        do {
            statusItemController = try StatusItemController(runtimeLogger: runtimeLogger)
            runtimeLogger.info("Status item controller initialized", metadata: ["logFile": runtimeLogger.logFileURL.path])
        } catch {
            runtimeLogger.error("Failed to initialize status item controller", error: error)
            showFatalStartupAlert(message: "OpenRouter Menu Bar could not finish launching. See runtime.log in Application Support/OpenRouterMenuBar for details.")
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showFatalStartupAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Launch Failed"
        alert.informativeText = message
        alert.runModal()
    }
}

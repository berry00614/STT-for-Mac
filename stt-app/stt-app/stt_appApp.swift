import SwiftUI
import Combine

/// NSApplicationDelegate for menu bar app lifecycle and permission setup.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let dictationService = DictationService()
    let transcriptionService = TranscriptionService()
    let captionWindowController = CaptionWindowController()
    let hudController = HUDPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app to accessory mode (no Dock icon, menu bar only)
        NSApp.setActivationPolicy(.accessory)

        // Start HUD observation
        hudController.observe(dictationService: dictationService)

        // Start hotkey monitoring
        startHotkeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        transcriptionService.stop()
        captionWindowController.close()
        hudController.hide()
    }

    // MARK: - Hotkey Setup

    private func startHotkeyMonitor() {
        let success = dictationService.startMonitoring()

        if !success {
            // Carbon RegisterEventHotKey requires Accessibility permission.
            // The same permission is used for paste (CGEventPost).
            // On first failure, request Accessibility and retry.
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            let trusted = AXIsProcessTrustedWithOptions(options)

            if !trusted {
                // Show help alert
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let alert = NSAlert()
                    alert.messageText = "Accessibility Access Required"
                    alert.informativeText = """
                        stt-app needs Accessibility access to detect the Right Option key and paste text.

                        Go to System Settings > Privacy & Security > Accessibility,
                        then enable stt-app. You may need to relaunch the app.

                        (No other permissions are needed — no Input Monitoring, no special entitlements.)
                        """
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open System Settings")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                }
            }
        } else {
            print("[AppDelegate] Hotkey monitor started successfully")
        }
    }
}

// MARK: - App

@main
struct stt_appApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar extra (always visible)
        MenuBarExtra {
            MenuBarView(
                dictationService: appDelegate.dictationService,
                transcriptionService: appDelegate.transcriptionService,
                captionWindowController: appDelegate.captionWindowController
            )
        } label: {
            let isActive = appDelegate.dictationService.state == .recording ||
                           appDelegate.dictationService.state == .transcribing ||
                           appDelegate.transcriptionService.isRunning

            Image(systemName: isActive ? "mic.fill" : "mic")
                .symbolRenderingMode(isActive ? .hierarchical : .monochrome)
                .foregroundStyle(isActive ? .red : .primary)
        }
        .menuBarExtraStyle(.menu)

        // Settings window (opened from menu bar)
        Window("Preferences", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 380)
    }
}

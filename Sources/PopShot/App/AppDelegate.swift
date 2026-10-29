import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// AppKit closes windows while quitting; window-close handlers check this so quitting
    /// isn't mistaken for the user dismissing a window.
    static private(set) var isTerminating = false

    private var menuBar: MenuBarController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        quitCleanlyOnSignals()
        LoginItem.refreshIfNeeded()

        if Prefs.instantMode { ThumbnailSetting.enableInstantMode() }

        CaptureCenter.shared.onCapture = { capture in
            PopupController.shared.show(capture)
        }
        CaptureCenter.shared.start()
        menuBar = MenuBarController()

        if !Prefs.onboarded { OnboardingWindow.show() }
        Log.info("PopShot \(AppInfo.version) started")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.isTerminating = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        ThumbnailSetting.restore()
    }

    /// There's no Dock icon, so opening the app again (Finder, Spotlight) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.show()
        return false
    }

    /// `pkill`, `brew uninstall` and Ctrl-C send signals. Quit through AppKit so
    /// Apple's floating-thumbnail setting is restored on the way out.
    private func quitCleanlyOnSignals() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}

import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    private func updateIcon() {
        let image = NSImage(systemSymbolName: Prefs.paused ? "pause.circle" : "camera.viewfinder",
                            accessibilityDescription: "PopShot")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let center = CaptureCenter.shared

        let header = NSMenuItem(title: "Watching \(center.folderDisplayName)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let problem = center.problem {
            let item = makeItem("⚠︎ \(problem.title)", #selector(fixProblem))
            item.toolTip = problem.detail
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let last = makeItem("Show Last Capture", #selector(showLastCapture))
        last.isEnabled = !Prefs.recentCaptures.isEmpty
        menu.addItem(last)

        let recent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for url in Prefs.recentCaptures {
            let item = makeItem(url.lastPathComponent, #selector(openRecent(_:)))
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            submenu.addItem(item)
        }
        if submenu.items.isEmpty {
            let none = NSMenuItem(title: "None yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        recent.submenu = submenu
        menu.addItem(recent)
        menu.addItem(.separator())

        let pause = makeItem("Pause PopShot", #selector(togglePause))
        pause.state = Prefs.paused ? .on : .off
        menu.addItem(pause)

        let instant = makeItem("Instant Pop-up", #selector(toggleInstant))
        instant.state = Prefs.instantMode ? .on : .off
        instant.toolTip = "Hides Apple's floating thumbnail so captures open immediately. Restored when PopShot quits."
        menu.addItem(instant)

        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Report a Bug…", #selector(reportBug)))
        menu.addItem(makeItem("PopShot on GitHub", #selector(openGitHub)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit PopShot", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showLastCapture() {
        guard let url = Prefs.recentCaptures.first, let capture = Capture(url: url) else { return }
        PopupController.shared.show(capture, automatic: false)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, let capture = Capture(url: url) else { return }
        PopupController.shared.show(capture, automatic: false)
    }

    @objc private func togglePause() {
        Prefs.paused.toggle()
        updateIcon()
    }

    @objc private func toggleInstant() {
        ThumbnailSetting.setInstantMode(!Prefs.instantMode)
    }

    @objc private func fixProblem() {
        CaptureCenter.shared.problem?.fix()
    }

    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func openGitHub() { NSWorkspace.shared.open(AppInfo.repoURL) }
    @objc private func reportBug() { NSWorkspace.shared.open(AppInfo.bugReportURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}

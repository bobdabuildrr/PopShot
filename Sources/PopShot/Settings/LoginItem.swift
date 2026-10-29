import Foundation

/// Launch at login through a LaunchAgent rather than SMAppService: macOS ties SMAppService
/// registrations to the app's code hash, and ad-hoc signed builds get a new hash on every
/// update, which would leave orphaned login items behind that the app can no longer remove.
enum LoginItem {
    private static let label = "app.popshot.PopShot"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        guard enabled else {
            try? FileManager.default.removeItem(at: agentURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: agentPlist, format: .xml, options: 0).write(to: agentURL)
        } catch {
            Log.error("Couldn't write LaunchAgent: \(error)")
        }
    }

    /// Called at launch: rewrites the agent if it's from an older version or the app has moved.
    static func refreshIfNeeded() {
        guard isEnabled,
              let data = try? Data(contentsOf: agentURL),
              let current = try? PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary,
              current != agentPlist as NSDictionary
        else { return }
        setEnabled(true)
    }

    /// Runs PopShot's own executable (so System Settings › Login Items lists it as "PopShot",
    /// not as "open from an unidentified developer").
    private static var agentPlist: [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [Bundle.main.executablePath ?? "/Applications/PopShot.app/Contents/MacOS/PopShot"],
            "AssociatedBundleIdentifiers": [label],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
    }
}

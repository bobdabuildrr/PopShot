import Foundation

/// Reads macOS's own screenshot preferences (the `com.apple.screencapture` domain,
/// which ⌘⇧5 › Options writes to).
enum ScreenshotSettings {
    private static let domain = "com.apple.screencapture" as CFString

    static func value(_ key: String) -> Any? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain)
    }

    /// The folder macOS saves screenshots and recordings into (⌘⇧5 › Options › Save to).
    static var saveFolder: URL {
        if let override = ProcessInfo.processInfo.environment["POPSHOT_WATCH_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let raw = value("location") as? String, !raw.isEmpty {
            let path = (raw as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Set with `defaults write com.apple.screencapture name "…"`; replaces the "Screenshot" prefix.
    static var customNamePrefix: String? {
        guard let name = value("name") as? String, !name.isEmpty else { return nil }
        return name
    }

    /// ⌘⇧5 › Options › Save to › Clipboard: no file is written, so there's nothing to open.
    static var savesToClipboard: Bool {
        (value("target") as? String) == "clipboard"
    }
}

/// Apple's floating thumbnail holds each new capture back for ~5 s before writing the file.
/// Instant mode turns it off while PopShot runs and restores the user's own choice on quit.
enum ThumbnailSetting {
    static func setInstantMode(_ on: Bool) {
        Prefs.instantMode = on
        if on { enableInstantMode() } else { restore() }
    }

    static func enableInstantMode() {
        if Prefs.thumbnailOriginal == nil {
            let current = ScreenshotSettings.value("show-thumbnail") as? Bool
            Prefs.thumbnailOriginal = current.map { $0 ? "true" : "false" } ?? "unset"
        }
        runDefaults(["write", "com.apple.screencapture", "show-thumbnail", "-bool", "false"])
        Log.info("Instant mode on: floating thumbnail hidden")
    }

    static func restore() {
        guard let original = Prefs.thumbnailOriginal else { return }
        if original == "unset" {
            runDefaults(["delete", "com.apple.screencapture", "show-thumbnail"])
        } else {
            runDefaults(["write", "com.apple.screencapture", "show-thumbnail", "-bool", original])
        }
        Prefs.thumbnailOriginal = nil
        Log.info("Floating thumbnail setting restored (\(original))")
    }

    private static func runDefaults(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.error("defaults \(arguments.joined(separator: " ")) failed: \(error)")
        }
    }
}

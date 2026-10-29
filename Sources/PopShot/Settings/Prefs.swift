import AppKit

enum PopupPlacement: String, CaseIterable, Identifiable {
    case center, bottomRight, remember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center: return "Center of the screen"
        case .bottomRight: return "Bottom-right corner"
        case .remember: return "Where I last moved it"
        }
    }
}

enum Prefs {
    enum Key {
        static let placement = "placement"
        static let autoCopy = "autoCopy"
        static let closeAfterCopy = "closeAfterCopy"
        static let closeOnClickOutside = "closeOnClickOutside"
        static let autoCloseSeconds = "autoCloseSeconds"
        static let showForScreenshots = "showForScreenshots"
        static let showForRecordings = "showForRecordings"
        static let paused = "paused"
        static let onboarded = "onboarded"
        static let instantMode = "instantMode"
        static let thumbnailOriginal = "thumbnailOriginal"
        static let recentCaptures = "recentCaptures"
        static let lastPopupCenter = "lastPopupCenter"
    }

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.placement: PopupPlacement.center.rawValue,
            Key.closeAfterCopy: true,
            Key.closeOnClickOutside: true,
            Key.autoCloseSeconds: 0,
            Key.showForScreenshots: true,
            Key.showForRecordings: true,
        ])
    }

    static var placement: PopupPlacement {
        PopupPlacement(rawValue: defaults.string(forKey: Key.placement) ?? "") ?? .center
    }
    static var autoCopy: Bool { defaults.bool(forKey: Key.autoCopy) }
    static var closeAfterCopy: Bool { defaults.bool(forKey: Key.closeAfterCopy) }
    static var closeOnClickOutside: Bool { defaults.bool(forKey: Key.closeOnClickOutside) }
    static var autoCloseSeconds: Int { defaults.integer(forKey: Key.autoCloseSeconds) }
    static var showForScreenshots: Bool { defaults.bool(forKey: Key.showForScreenshots) }
    static var showForRecordings: Bool { defaults.bool(forKey: Key.showForRecordings) }

    static var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }
    static var onboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }
    static var instantMode: Bool {
        get { defaults.bool(forKey: Key.instantMode) }
        set { defaults.set(newValue, forKey: Key.instantMode) }
    }
    /// The user's own `show-thumbnail` value ("true", "false" or "unset") while PopShot has it turned off.
    static var thumbnailOriginal: String? {
        get { defaults.string(forKey: Key.thumbnailOriginal) }
        set { defaults.set(newValue, forKey: Key.thumbnailOriginal) }
    }
    static var lastPopupCenter: CGPoint? {
        get { defaults.string(forKey: Key.lastPopupCenter).map { NSPointFromString($0) } }
        set { defaults.set(newValue.map { NSStringFromPoint($0) }, forKey: Key.lastPopupCenter) }
    }

    static var recentCaptures: [URL] {
        (defaults.stringArray(forKey: Key.recentCaptures) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func addRecent(_ url: URL) {
        var paths = defaults.stringArray(forKey: Key.recentCaptures) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(10)), forKey: Key.recentCaptures)
    }

    static func removeRecent(_ url: URL) {
        let paths = (defaults.stringArray(forKey: Key.recentCaptures) ?? []).filter { $0 != url.path }
        defaults.set(paths, forKey: Key.recentCaptures)
    }
}

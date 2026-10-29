import AppKit
import CoreServices

/// Watches the screenshot folder and hands each new capture to `onCapture` on the main queue.
final class CaptureCenter {
    static let shared = CaptureCenter()

    enum Problem {
        case noFolderAccess(URL)
        case savesToClipboard

        var title: String {
            switch self {
            case .noFolderAccess: return "PopShot can't read your screenshot folder"
            case .savesToClipboard: return "Screenshots are set to go to the clipboard"
            }
        }

        var detail: String {
            switch self {
            case .noFolderAccess(let folder):
                return "Allow PopShot to access \(folder.lastPathComponent) in System Settings › Privacy & Security › Files and Folders."
            case .savesToClipboard:
                return "Press ⌘⇧5 › Options and choose a folder under “Save to” so PopShot can open your captures."
            }
        }

        func fix() {
            switch self {
            case .noFolderAccess:
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
            case .savesToClipboard:
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = detail
                alert.runModal()
            }
        }
    }

    var onCapture: ((Capture) -> Void)?
    private(set) var folder: URL?
    private(set) var problem: Problem?

    private let watcher = FolderWatcher()
    private let launchDate = Date()
    private var handled = Set<String>()
    private var suppressed: [String: Date] = [:]
    private var timer: Timer?

    var folderDisplayName: String {
        folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "…"
    }

    func start() {
        refresh()
        // ⌘⇧5 › Options › Save to can change at any time; follow it.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// Ignore events for a file PopShot itself is about to write (edits, trims, Save As).
    func suppress(_ url: URL) {
        suppressed[Self.canonicalPath(url)] = Date()
    }

    /// FSEvents reports real paths (`/private/tmp/…`), so resolve the folder part the same way.
    private static func canonicalPath(_ url: URL) -> String {
        realPath(url.deletingLastPathComponent().path) + "/" + url.lastPathComponent
    }

    private func refresh() {
        let target = ScreenshotSettings.saveFolder.standardizedFileURL
        problem = findProblem(in: target)
        guard target != folder else { return }
        folder = target
        Log.info("Watching \(target.path)")
        watcher.start(folder: target) { [weak self] url in self?.consider(url) }
    }

    private func findProblem(in folder: URL) -> Problem? {
        if ScreenshotSettings.savesToClipboard { return .savesToClipboard }
        // Opening the folder is also what triggers macOS's one-time "access Desktop?" prompt.
        guard let directory = opendir(folder.path) else { return .noFolderAccess(folder) }
        closedir(directory)
        return nil
    }

    private func consider(_ url: URL) {
        let now = Date()
        suppressed = suppressed.filter { now.timeIntervalSince($0.value) < 10 }
        guard !Prefs.paused, suppressed[Self.canonicalPath(url)] == nil,
              let kind = CaptureClassifier.classify(url, notBefore: launchDate),
              let id = Self.fileIdentity(url),
              handled.insert(id).inserted
        else { return }

        if kind == .image && !Prefs.showForScreenshots { return }
        if kind == .video && !Prefs.showForRecordings { return }

        Log.info("New capture: \(url.lastPathComponent)")
        Prefs.addRecent(url)
        let capture = Capture(url: url, kind: kind)
        if kind == .video {
            deliverWhenComplete(capture)
        } else {
            onCapture?(capture)
        }
    }

    /// Each file produces several events (temp file, rename, metadata). Inode + creation date
    /// identifies it even after the user renames it.
    private static func fileIdentity(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let created = attributes[.creationDate] as? Date
        else { return nil }
        return "\(inode.uint64Value)-\(created.timeIntervalSinceReferenceDate)"
    }

    /// Recordings can still be growing when they appear; wait for the size to settle.
    private func deliverWhenComplete(_ capture: Capture, lastSize: Int64 = -1, attempt: Int = 0) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: capture.url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        if size < 0 && attempt > 10 { return }
        if size > 0 && (size == lastSize || attempt > 150) {
            onCapture?(capture)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.deliverWhenComplete(capture, lastSize: size, attempt: attempt + 1)
        }
    }
}

/// FSEvents stream on a single folder, reporting files created or renamed directly inside it.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var handler: ((URL) -> Void)?
    private var folderPath = ""

    func start(folder: URL, handler: @escaping (URL) -> Void) {
        stop()
        self.handler = handler
        folderPath = realPath(folder.path)

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            for index in 0..<count {
                watcher.received(path: paths[index], flags: flags[index])
            }
        }
        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [folderPath] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, createFlags)
        else {
            Log.error("Couldn't watch \(folderPath)")
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func received(path: String, flags: FSEventStreamEventFlags) {
        let isFile = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0
        let changes = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified
        )
        let url = URL(fileURLWithPath: path)
        guard isFile, flags & changes != 0, url.deletingLastPathComponent().path == folderPath else { return }
        handler?(url)
    }
}

/// `realpath(3)`. Unlike `URL.resolvingSymlinksInPath()`, it keeps the `/private` prefix FSEvents uses.
func realPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

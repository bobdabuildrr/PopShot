import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// Owns the single pop-up window: shows captures, routes keyboard shortcuts and runs every action.
final class PopupController: NSObject, NSWindowDelegate {
    static let shared = PopupController()

    private var panel: PopupPanel?
    private(set) var model: PopupModel?
    private var pending: Capture?
    private var autoCloseTimer: Timer?
    private var generation = 0
    private var isRunningModal = false
    private var clickMonitor: Any?
    private var discardArmedAt: Date?

    private let toolbarHeight: CGFloat = 48

    // MARK: Showing and closing

    /// `automatic` is true for brand-new captures (as opposed to ones reopened from the menu).
    func show(_ capture: Capture, automatic: Bool = true) {
        if let model, model.editor != nil, panel?.isVisible == true {
            pending = capture
            HUD.show("New capture saved. It opens when you finish editing.", symbol: "camera.viewfinder")
            return
        }
        if capture.kind == .video {
            VideoModel.load(capture.url) { [weak self] video in
                self?.present(PopupModel(capture: capture, video: video), automatic: automatic)
            }
        } else {
            present(PopupModel(capture: capture), automatic: automatic)
        }
    }

    private func present(_ model: PopupModel, automatic: Bool) {
        guard model.isLoaded else {
            Log.error("Couldn't open \(model.capture.url.lastPathComponent)")
            return
        }
        if automatic, Prefs.autoCopy { copyToClipboard(model) }

        generation += 1
        self.model = model
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: PopupRootView(model: model, controller: self))
        host.sizingOptions = []
        panel.contentView = host
        present(panel, frame: viewingFrame(for: model, on: currentScreen()))
        startWatchingOutsideClicks()
        scheduleAutoClose()
    }

    func close() {
        autoCloseTimer?.invalidate()
        stopWatchingOutsideClicks()
        guard let panel, panel.isVisible else { return }
        model?.video?.player.pause()
        let closing = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == closing else { return }
            panel.orderOut(nil)
            panel.contentView = nil
            self.model = nil
            if let next = self.pending {
                self.pending = nil
                self.show(next, automatic: false)
            }
        })
    }

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                               styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.controller = self
        panel.delegate = self
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceChanged),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.minSize = NSSize(width: 480, height: 260)
        return panel
    }

    private func present(_ panel: PopupPanel, frame: NSRect) {
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrame(frame.insetBy(dx: frame.width * 0.03, dy: frame.height * 0.03), display: false)
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        panel.makeKey()
    }

    // MARK: Layout

    private func currentScreen() -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func fittedSize(for model: PopupModel, in visible: NSRect, fraction: CGSize, minWidth: CGFloat) -> NSSize {
        var image = CGSize(width: model.pixelSize.width / model.pixelsPerPoint, height: model.pixelSize.height / model.pixelsPerPoint)
        if image.width < 1 || image.height < 1 { image = CGSize(width: 800, height: 500) }
        let padding: CGFloat = 24
        let maxWidth = visible.width * fraction.width - padding
        let maxHeight = visible.height * fraction.height - toolbarHeight - padding
        let scale = min(1, maxWidth / image.width, maxHeight / image.height)
        let width = min(max(image.width * scale + padding, minWidth), visible.width - 32)
        let height = min(max(image.height * scale + padding, 220) + toolbarHeight, visible.height - 32)
        return NSSize(width: width, height: height)
    }

    private func viewingFrame(for model: PopupModel, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let placement = Prefs.placement
        let fraction = placement == .bottomRight ? CGSize(width: 0.34, height: 0.42) : CGSize(width: 0.62, height: 0.74)
        let size = fittedSize(for: model, in: visible, fraction: fraction, minWidth: 560)

        switch placement {
        case .bottomRight:
            return NSRect(x: visible.maxX - size.width - 16, y: visible.minY + 16, width: size.width, height: size.height)
        case .remember:
            if let center = Prefs.lastPopupCenter, visible.contains(center) {
                return clamp(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                    width: size.width, height: size.height), to: visible)
            }
            fallthrough
        case .center:
            return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
    }

    /// Grows the window (never shrinks it) so the editing toolbar fits, keeping it where it is.
    private func editingFrame(for model: PopupModel, around current: NSRect) -> NSRect {
        let visible = panel?.screen?.visibleFrame ?? currentScreen().visibleFrame
        let wanted = fittedSize(for: model, in: visible, fraction: CGSize(width: 0.7, height: 0.8), minWidth: 860)
        let size = NSSize(width: max(current.width, wanted.width), height: max(current.height, wanted.height))
        return clamp(NSRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2,
                            width: size.width, height: size.height), to: visible)
    }

    private func refit(_ model: PopupModel) {
        guard let panel else { return }
        let visible = panel.screen?.visibleFrame ?? currentScreen().visibleFrame
        let size = fittedSize(for: model, in: visible, fraction: CGSize(width: 0.62, height: 0.74), minWidth: 560)
        let current = panel.frame
        present(panel, frame: clamp(NSRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2,
                                           width: size.width, height: size.height), to: visible))
    }

    private func clamp(_ rect: NSRect, to visible: NSRect) -> NSRect {
        var r = rect
        r.size.width = min(r.width, visible.width)
        r.size.height = min(r.height, visible.height)
        r.origin.x = min(max(r.minX, visible.minX), visible.maxX - r.width)
        r.origin.y = min(max(r.minY, visible.minY), visible.maxY - r.height)
        return r
    }

    // MARK: Auto-close

    private func scheduleAutoClose() {
        autoCloseTimer?.invalidate()
        let seconds = Prefs.autoCloseSeconds
        guard seconds > 0 else { return }
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible, self.model?.editor == nil else { return }
            if NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) {
                self.scheduleAutoClose() // don't vanish from under the pointer
            } else {
                self.close()
            }
        }
    }

    /// "Close when I click somewhere else" means a real click in another app. Losing focus alone
    /// doesn't count: swiping to another desktop or ⌘-Tab keeps the pop-up open (it follows you to
    /// every desktop), so you can drop the capture into an app over there.
    private func startWatchingOutsideClicks() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self else { return }
            // PopShot is never the active app, so macOS reports clicks on its own pop-up (and pins)
            // to this "other apps" monitor too. Only close for clicks outside every PopShot window.
            let point = NSEvent.mouseLocation
            if let panel = self.panel, panel.isVisible, panel.frame.contains(point) {
                // Another panel (e.g. Spotlight) may have held the keyboard; take it back so ⌘C works.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { panel.makeKey() }
                return
            }
            guard Prefs.closeOnClickOutside, !self.isRunningModal, let model = self.model,
                  model.editor == nil, model.video?.isTrimming != true else { return }
            if NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(point) }) { return }
            self.close()
        }
    }

    private func stopWatchingOutsideClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// After switching desktops, take the keyboard back so shortcuts keep working.
    @objc private func activeSpaceChanged() {
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
    }

    func windowDidMove(_ notification: Notification) {
        guard Prefs.placement == .remember, let panel, panel.isVisible, panel.alphaValue > 0.9 else { return }
        Prefs.lastPopupCenter = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
    }

    // MARK: Keyboard

    /// Plain keys (no ⌘). Returns true when handled.
    func handleKey(_ event: NSEvent) -> Bool {
        // While trimming, keys (Esc = cancel, Return = trim) belong to the player's trimmer.
        guard let model, model.video?.isTrimming != true else { return false }
        autoCloseTimer?.invalidate()
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isDelete = event.keyCode == 51 || event.keyCode == 117

        if event.keyCode == 53 {
            escape()
            return true
        }
        guard flags.isEmpty else { return false }

        if let editor = model.editor {
            if isDelete, let id = editor.selection {
                editor.remove(id)
                return true
            }
            if let tool = Tool.allCases.first(where: { $0.key == key }) {
                editor.choose(tool)
                return true
            }
            return false
        }

        if isDelete {
            trash()
            return true
        }
        switch (model.capture.kind, key) {
        case (.image, "e"): edit()
        case (.image, "p"): pin()
        case (.video, "t"): trim()
        case (.video, " "): model.video?.togglePlayback()
        default: return false
        }
        return true
    }

    /// ⌘ shortcuts. Returns true when handled.
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        autoCloseTimer?.invalidate()
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shift = flags.contains(.shift)

        if let editor = model.editor {
            switch (key, shift) {
            case ("z", false): editor.undo()
            case ("z", true): editor.redo()
            case ("c", false): copyEdited()
            case ("s", _): saveEditedCopy()
            case ("\r", _): finishEdit()
            case ("w", _): escape()
            default: return false
            }
            return true
        }

        switch (key, shift) {
        case ("c", false): copyCapture()
        case ("c", true) where model.capture.kind == .image: copyText()
        case ("s", _): saveAs()
        case ("r", _): reveal()
        case ("o", _): openInDefaultApp()
        case ("w", _): close()
        default:
            guard event.keyCode == 51 else { return false }
            trash()
        }
        return true
    }

    func escape() {
        guard let model, model.video?.isTrimming != true else { return }
        guard let editor = model.editor else {
            close()
            return
        }
        if editor.selection != nil {
            editor.selection = nil
            return
        }
        let armed = discardArmedAt.map { Date().timeIntervalSince($0) < 2 } ?? false
        if editor.hasChanges && !armed {
            discardArmedAt = Date()
            HUD.show("Press Esc again to discard your edits", symbol: "exclamationmark.circle")
            return
        }
        cancelEdit()
    }

    // MARK: Viewer actions

    func copyCapture() {
        guard let model else { return }
        guard copyToClipboard(model) else {
            HUD.show("Couldn't copy", symbol: "exclamationmark.triangle.fill")
            return
        }
        HUD.show(model.capture.kind == .video ? "Copied video" : "Copied", symbol: "doc.on.doc.fill")
        if Prefs.closeAfterCopy { close() }
    }

    @discardableResult
    private func copyToClipboard(_ model: PopupModel) -> Bool {
        switch model.capture.kind {
        case .image:
            return Clipboard.copyImage(at: model.capture.url)
        case .video:
            Clipboard.copyFile(model.capture.url)
            return true
        }
    }

    func copyText() {
        guard let model, model.capture.kind == .image else { return }
        OCR.recognizeText(in: model.capture.url) { [weak self] text in
            guard let text, !text.isEmpty else {
                HUD.show("No text found", symbol: "text.viewfinder")
                return
            }
            Clipboard.copyText(text)
            let lines = text.split(separator: "\n").count
            HUD.show("Copied \(lines) line\(lines == 1 ? "" : "s") of text", symbol: "text.viewfinder")
            if Prefs.closeAfterCopy, self?.model === model { self?.close() }
        }
    }

    func saveAs() {
        guard let model else { return }
        let source = model.capture.url
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = source.lastPathComponent
        if let type = UTType(filenameExtension: source.pathExtension) { savePanel.allowedContentTypes = [type] }
        savePanel.canCreateDirectories = true

        // The save panel needs PopShot to be the active app; hand focus back afterwards. Keep
        // `isRunningModal` set a moment longer so that hand-back doesn't count as a click outside.
        let previousApp = NSWorkspace.shared.frontmostApplication
        isRunningModal = true
        NSApp.activate(ignoringOtherApps: true)
        let response = savePanel.runModal()
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isRunningModal = false }

        guard response == .OK, let destination = savePanel.url else {
            panel?.makeKey()
            return
        }
        CaptureCenter.shared.suppress(destination)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination) // the save panel already asked to replace
            }
            try FileManager.default.copyItem(at: source, to: destination)
            HUD.show("Saved to \(destination.deletingLastPathComponent().lastPathComponent)", symbol: "square.and.arrow.down.fill")
            close()
        } catch {
            HUD.show("Couldn't save: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    func trash() {
        guard let model else { return }
        model.video?.player.pause()
        do {
            try FileManager.default.trashItem(at: model.capture.url, resultingItemURL: nil)
            Prefs.removeRecent(model.capture.url)
            close()
            HUD.show("Moved to Trash", symbol: "trash.fill")
        } catch {
            HUD.show("Couldn't move to Trash", symbol: "exclamationmark.triangle.fill")
        }
    }

    func reveal() {
        guard let model else { return }
        NSWorkspace.shared.activateFileViewerSelecting([model.capture.url])
        close()
    }

    func openInDefaultApp() {
        guard let model else { return }
        NSWorkspace.shared.open(model.capture.url)
        close()
    }

    func pin() {
        guard let model, let image = model.image else { return }
        PinWindow.pin(image, url: model.capture.url)
        close()
    }

    // MARK: Video

    func trim() {
        guard let model, let video = model.video, let playerView = video.playerView, playerView.canBeginTrimming else { return }
        autoCloseTimer?.invalidate()
        video.isTrimming = true
        let source = model.capture.url
        playerView.beginTrimming { [weak self] result in
            video.isTrimming = false
            guard result == .okButton, let item = video.player.currentItem else { return }
            let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
            let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
            self?.exportTrim(of: item.asset, range: CMTimeRange(start: start, end: end), source: source)
        }
        panel?.makeFirstResponder(playerView)
    }

    private func exportTrim(of asset: AVAsset, range: CMTimeRange, source: URL) {
        let destination = FileNaming.sibling(of: source, suffix: "trimmed")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            HUD.show("Couldn't trim this video", symbol: "exclamationmark.triangle.fill")
            return
        }
        session.outputURL = destination
        session.outputFileType = source.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        session.timeRange = range
        CaptureCenter.shared.suppress(destination)
        HUD.show("Trimming…", symbol: "scissors")
        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard session.status == .completed else {
                    HUD.show("Trim failed", symbol: "exclamationmark.triangle.fill")
                    return
                }
                Prefs.addRecent(destination)
                HUD.show("Saved \(destination.lastPathComponent)", symbol: "scissors")
                self?.show(Capture(url: destination, kind: .video), automatic: false)
            }
        }
    }

    // MARK: Editing

    func edit() {
        guard let model, model.capture.kind == .image, model.editor == nil,
              let loaded = ImageFiles.load(model.capture.url) else { return }
        autoCloseTimer?.invalidate()
        discardArmedAt = nil
        model.editor = EditorModel(image: loaded.image, pixelsPerPoint: loaded.pixelsPerPoint)
        model.editor?.requestDone = { [weak self] in self?.finishEdit() }
        if let panel { present(panel, frame: editingFrame(for: model, around: panel.frame)) }
    }

    /// Done: saves over the original, like Apple's Markup.
    func finishEdit() {
        guard let model, let editor = model.editor else { return }
        editor.commitPendingText?()
        guard editor.hasChanges else {
            leaveEditing()
            return
        }
        let original = model.capture.url
        let target = ImageFiles.canWrite(extension: original.pathExtension)
            ? original
            : FileNaming.sibling(of: original, suffix: "edited", extension: "png")
        guard save(editor, to: target) else { return }
        model.replace(with: Capture(url: target, kind: .image))
        HUD.show("Saved")
        leaveEditing()
    }

    func saveEditedCopy() {
        guard let model, let editor = model.editor else { return }
        let source = model.capture.url
        let ext = ImageFiles.canWrite(extension: source.pathExtension) ? source.pathExtension : "png"
        let target = FileNaming.sibling(of: source, suffix: "edited", extension: ext)
        guard save(editor, to: target) else { return }
        Prefs.addRecent(target)
        model.replace(with: Capture(url: target, kind: .image))
        HUD.show("Saved \(target.lastPathComponent)")
        leaveEditing()
    }

    func copyEdited() {
        guard let editor = model?.editor, let image = editor.render() else { return }
        Clipboard.copy(image, pixelsPerPoint: editor.pixelsPerPoint)
        HUD.show("Copied edited image", symbol: "doc.on.doc.fill")
    }

    func cancelEdit() {
        leaveEditing()
    }

    private func save(_ editor: EditorModel, to url: URL) -> Bool {
        guard let image = editor.render() else {
            HUD.show("Couldn't render the image", symbol: "exclamationmark.triangle.fill")
            return false
        }
        CaptureCenter.shared.suppress(url)
        do {
            try ImageFiles.write(image, to: url, pixelsPerPoint: editor.pixelsPerPoint)
            return true
        } catch {
            Log.error("Save failed: \(error)")
            HUD.show("Couldn't save: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
            return false
        }
    }

    private func leaveEditing() {
        guard let model else { return }
        model.editor = nil
        discardArmedAt = nil
        refit(model)
        if let next = pending {
            pending = nil
            show(next, automatic: false)
        }
    }
}

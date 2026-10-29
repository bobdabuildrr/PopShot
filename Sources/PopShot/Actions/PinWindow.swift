import AppKit

/// Keeps a capture floating above every window, like a sticky note.
/// Drag to move, scroll to resize, ⌥-scroll for opacity, double-click or Esc to close.
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []

    static func pin(_ image: NSImage, url: URL) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame, image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(1, visible.width * 0.4 / image.size.width, visible.height * 0.4 / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let offset = CGFloat(open.count % 6) * 24
        let frame = NSRect(x: visible.maxX - size.width - 24 - offset, y: visible.maxY - size.height - 24 - offset,
                           width: size.width, height: size.height)
        let window = PinWindow(image: image, url: url, frame: frame)
        open.append(window)
        window.orderFrontRegardless()
    }

    private init(image: NSImage, url: URL, frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentView = PinImageView(image: image, url: url)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        super.close()
        PinWindow.open.removeAll { $0 === self }
    }

    fileprivate func resize(by factor: CGFloat) {
        guard let visible = screen?.visibleFrame else { return }
        let width = min(max(frame.width * factor, 80), visible.width)
        let height = width * frame.height / frame.width
        setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), display: true)
    }
}

private final class PinImageView: NSView {
    private let image: NSImage
    private let url: URL

    init(image: NSImage, url: URL) {
        self.image = image
        self.url = url
        super.init(frame: .zero)
        toolTip = "Drag to move · scroll to resize · ⌥-scroll for opacity · double-click to close"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        path.addClip()
        image.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.2).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.close()
        } else {
            window?.makeKey()
            window?.performDrag(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window = window as? PinWindow else { return }
        if event.modifierFlags.contains(.option) {
            window.alphaValue = min(1, max(0.2, window.alphaValue + event.scrollingDeltaY * 0.01))
        } else {
            window.resize(by: 1 + event.scrollingDeltaY * 0.01)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show in Finder", action: #selector(reveal), keyEquivalent: "").target = self
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let levels = NSMenu()
        for percent in [100, 75, 50, 25] {
            let item = levels.addItem(withTitle: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = percent
        }
        opacity.submenu = levels
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(closePin), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copyImage() { Clipboard.copyImage(at: url) }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    @objc private func setOpacity(_ sender: NSMenuItem) { window?.alphaValue = CGFloat(sender.tag) / 100 }
    @objc private func closePin() { window?.close() }
}

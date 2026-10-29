import AppKit

/// A floating panel that takes keyboard input without activating PopShot, so the app
/// you were using stays frontmost (like Spotlight).
final class PopupPanel: NSPanel {
    weak var controller: PopupController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.escape()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if firstResponder is NSText, TextEditingShortcuts.perform(event) { return true }
        if controller?.handleKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// PopShot has no Edit menu (it never becomes the active app), so text boxes need
/// ⌘X/C/V/A/Z wired up by hand.
enum TextEditingShortcuts {
    static func perform(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift] else { return false }
        let selector: Selector
        switch (event.charactersIgnoringModifiers?.lowercased() ?? "", flags.contains(.shift)) {
        case ("x", false): selector = #selector(NSText.cut(_:))
        case ("c", false): selector = #selector(NSText.copy(_:))
        case ("v", false): selector = #selector(NSText.paste(_:))
        case ("a", false): selector = #selector(NSText.selectAll(_:))
        case ("z", false): selector = Selector(("undo:"))
        case ("z", true): selector = Selector(("redo:"))
        default: return false
        }
        return NSApp.sendAction(selector, to: nil, from: nil)
    }
}

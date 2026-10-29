import AppKit

enum Clipboard {
    @discardableResult
    static func copyImage(at url: URL) -> Bool {
        guard let loaded = ImageFiles.load(url) else { return false }
        return copy(loaded.image, pixelsPerPoint: loaded.pixelsPerPoint)
    }

    /// PNG for modern apps (Slack, browsers, Figma), TIFF for older Cocoa apps.
    @discardableResult
    static func copy(_ image: CGImage, pixelsPerPoint: CGFloat) -> Bool {
        guard let png = ImageFiles.pngData(image, pixelsPerPoint: pixelsPerPoint) else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / pixelsPerPoint, height: CGFloat(image.height) / pixelsPerPoint)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        return true
    }

    /// Videos are copied as files, which paste as attachments in Slack, Mail, Messages and Finder.
    static func copyFile(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

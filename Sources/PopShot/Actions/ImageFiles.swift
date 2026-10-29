import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageFiles {
    struct Loaded {
        let image: CGImage
        /// 2 for Retina screenshots (saved at 144 dpi), 1 otherwise.
        let pixelsPerPoint: CGFloat
    }

    enum SaveError: LocalizedError {
        case unsupportedFormat, writeFailed
        var errorDescription: String? {
            self == .unsupportedFormat ? "That file format can't be written." : "The image couldn't be written."
        }
    }

    static func load(_ url: URL) -> Loaded? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
            return Loaded(image: image, pixelsPerPoint: max(1, CGFloat(dpi / 72).rounded()))
        }
        return rasterize(url)
    }

    /// PDF screenshots (and anything else ImageIO can't decode) are drawn at 2×.
    private static func rasterize(_ url: URL) -> Loaded? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage.map { Loaded(image: $0, pixelsPerPoint: 2) }
    }

    static func canWrite(extension ext: String) -> Bool {
        guard let type = UTType(filenameExtension: ext.lowercased()) else { return false }
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return supported.contains(type.identifier) && type != .pdf
    }

    /// Writes to a hidden temp file first, so a failed save never damages the original.
    static func write(_ image: CGImage, to url: URL, pixelsPerPoint: CGFloat) throws {
        let ext = url.pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext), canWrite(extension: ext) else { throw SaveError.unsupportedFormat }
        let temp = url.deletingLastPathComponent().appendingPathComponent(".popshot-\(UUID().uuidString).\(ext)")
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type.identifier as CFString, 1, nil) else {
            throw SaveError.writeFailed
        }
        CGImageDestinationAddImage(destination, image, dpiProperties(pixelsPerPoint))
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temp)
            throw SaveError.writeFailed
        }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }

    static func pngData(_ image: CGImage, pixelsPerPoint: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, dpiProperties(pixelsPerPoint))
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func dpiProperties(_ pixelsPerPoint: CGFloat) -> CFDictionary {
        let dpi = 72 * pixelsPerPoint
        return [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
    }
}

enum FileNaming {
    /// "Screenshot ….png" → "Screenshot … (edited).png", then "(edited 2)" and so on.
    static func sibling(of url: URL, suffix: String, extension ext: String? = nil) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = ext ?? url.pathExtension
        var number = 1
        while true {
            let label = number == 1 ? suffix : "\(suffix) \(number)"
            let candidate = folder.appendingPathComponent("\(base) (\(label))").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}

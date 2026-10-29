import Foundation

enum CaptureKind {
    case image, video
}

struct Capture: Equatable {
    let url: URL
    let kind: CaptureKind

    init(url: URL, kind: CaptureKind) {
        self.url = url
        self.kind = kind
    }

    init?(url: URL) {
        guard let kind = CaptureClassifier.kind(forExtension: url.pathExtension) else { return nil }
        self.init(url: url, kind: kind)
    }
}

enum CaptureClassifier {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "pdf"]
    static let videoExtensions: Set<String> = ["mov", "mp4"]

    static func kind(forExtension ext: String) -> CaptureKind? {
        let ext = ext.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        return nil
    }

    /// The capture kind when `url` is a screenshot or screen recording macOS wrote after `notBefore`.
    static func classify(_ url: URL, notBefore: Date) -> CaptureKind? {
        let name = url.lastPathComponent
        guard !name.hasPrefix("."), let kind = kind(forExtension: url.pathExtension) else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              let created = attributes[.creationDate] as? Date,
              created >= notBefore
        else { return nil }
        return isMarkedAsScreenCapture(url) || hasSystemCaptureName(name) ? kind : nil
    }

    /// macOS tags every screenshot with this extended attribute (it's what Spotlight indexes).
    static func isMarkedAsScreenCapture(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
        }
    }

    /// Fallback for files without the attribute, such as screen recordings.
    static func hasSystemCaptureName(_ name: String) -> Bool {
        var prefixes = ["Screenshot", "Screen Shot", "Screen Recording"]
        if let custom = ScreenshotSettings.customNamePrefix { prefixes.append(custom) }
        return prefixes.contains { name.hasPrefix($0) }
    }
}

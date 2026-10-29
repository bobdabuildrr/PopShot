import AppKit

enum Tool: String, CaseIterable, Identifiable {
    case select, arrow, rect, pen, highlight, text, blur, crop

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .pen: return "scribble"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .blur: return "eye.slash"
        case .crop: return "crop"
        }
    }

    /// Single-key shortcut while editing.
    var key: String {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .rect: return "r"
        case .pen: return "p"
        case .highlight: return "h"
        case .text: return "t"
        case .blur: return "b"
        case .crop: return "c"
        }
    }

    var help: String {
        let name: String
        switch self {
        case .select: name = "Select & move"
        case .arrow: name = "Arrow"
        case .rect: name = "Rectangle"
        case .pen: name = "Pen"
        case .highlight: name = "Highlight"
        case .text: name = "Text"
        case .blur: name = "Blur (pixelate)"
        case .crop: name = "Crop"
        }
        return "\(name) (\(key.uppercased()))"
    }
}

enum Palette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1),
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    ]
    /// In points; multiplied by the image's pixels-per-point so Retina captures look the same.
    static let strokeWidths: [CGFloat] = [2, 4, 7]
    static let fontSizes: [CGFloat] = [15, 22, 32]
}

/// A mark on the image. All geometry is in image pixels with a top-left origin.
struct Annotation: Identifiable, Equatable {
    enum Shape: Equatable {
        case arrow(CGPoint, CGPoint)
        case rect(CGRect)
        case pen([CGPoint])
        case highlight(CGRect)
        case text(CGPoint, String)
        case blur(CGRect)
    }

    var id = UUID()
    var shape: Shape
    var color: NSColor
    var width: CGFloat
    var fontSize: CGFloat

    static func font(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    static func textAttributes(color: NSColor, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = fontSize * 0.08
        shadow.shadowOffset = .zero
        return [.font: font(size: fontSize), .foregroundColor: color, .shadow: shadow]
    }

    var text: String? {
        if case let .text(_, string) = shape { return string }
        return nil
    }

    var bounds: CGRect {
        switch shape {
        case let .arrow(a, b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .insetBy(dx: -width * 2, dy: -width * 2)
        case let .rect(r), let .highlight(r), let .blur(r):
            return r.standardized.insetBy(dx: -width / 2, dy: -width / 2)
        case let .pen(points):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -width, dy: -width)
        case let .text(origin, string):
            let size = NSAttributedString(string: string, attributes: Self.textAttributes(color: color, fontSize: fontSize)).size()
            return CGRect(origin: origin, size: size)
        }
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if case let .arrow(a, b) = shape {
            return Self.distance(from: point, toSegment: a, b) <= max(width * 2, tolerance)
        }
        return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }

    func offset(by delta: CGSize) -> Annotation {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.width, y: p.y + delta.height) }
        func move(_ r: CGRect) -> CGRect { r.offsetBy(dx: delta.width, dy: delta.height) }
        var copy = self
        switch shape {
        case let .arrow(a, b): copy.shape = .arrow(move(a), move(b))
        case let .rect(r): copy.shape = .rect(move(r))
        case let .pen(points): copy.shape = .pen(points.map(move))
        case let .highlight(r): copy.shape = .highlight(move(r))
        case let .text(origin, string): copy.shape = .text(move(origin), string)
        case let .blur(r): copy.shape = .blur(move(r))
        }
        return copy
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

struct EditState: Equatable {
    var annotations: [Annotation] = []
    /// Applied last, on export.
    var crop: CGRect?
}

import AppKit
import CoreImage

/// Draws the image plus annotations. The canvas preview and the full-resolution export
/// share this code, so what you see is exactly what gets saved.
final class SceneRenderer {
    let base: CGImage
    let size: CGSize
    private static let ciContext = CIContext(options: nil)
    private lazy var pixelated: CGImage? = Self.pixelate(base)

    init(base: CGImage) {
        self.base = base
        size = CGSize(width: base.width, height: base.height)
    }

    /// `context` must use image-pixel units with a top-left origin.
    func drawScene(in context: CGContext, annotations: [Annotation]) {
        Self.drawImage(base, in: CGRect(origin: .zero, size: size), context: context)
        for annotation in annotations {
            draw(annotation, in: context)
        }
    }

    func export(state: EditState) -> CGImage? {
        let colorSpace = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawScene(in: context, annotations: state.annotations)
        NSGraphicsContext.restoreGraphicsState()

        guard let full = context.makeImage() else { return nil }
        guard let crop = state.crop?.integral.intersection(CGRect(origin: .zero, size: size)),
              crop.width >= 1, crop.height >= 1
        else { return full }
        return full.cropping(to: crop)
    }

    /// Draws a CGImage upright inside a flipped (top-left origin) context.
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    private func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let color = annotation.color.cgColor
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(annotation.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.shape {
        case let .arrow(from, to):
            drawArrow(from: from, to: to, width: annotation.width, in: context)

        case let .rect(rect):
            let r = rect.standardized
            let radius = min(annotation.width, r.width / 2, r.height / 2)
            context.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()

        case let .pen(points):
            guard points.count > 1 else { return }
            context.addLines(between: points)
            context.strokePath()

        case let .highlight(rect):
            context.setBlendMode(.multiply)
            context.setFillColor(annotation.color.withAlphaComponent(0.45).cgColor)
            context.fill(rect.standardized)

        case let .text(origin, string):
            NSAttributedString(string: string,
                               attributes: Annotation.textAttributes(color: annotation.color, fontSize: annotation.fontSize))
                .draw(at: origin)

        case let .blur(rect):
            let r = rect.standardized
            context.clip(to: r)
            if let pixelated {
                Self.drawImage(pixelated, in: CGRect(origin: .zero, size: size), context: context)
            } else {
                context.setFillColor(NSColor.gray.cgColor)
                context.fill(r)
            }
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, in context: CGContext) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }
        let ux = dx / length, uy = dy / length
        let head = min(max(width * 4.5, 14), length * 0.6)
        let neck = CGPoint(x: end.x - ux * head * 0.8, y: end.y - uy * head * 0.8)
        let back = CGPoint(x: end.x - ux * head, y: end.y - uy * head)
        let left = CGPoint(x: back.x - uy * head * 0.55, y: back.y + ux * head * 0.55)
        let right = CGPoint(x: back.x + uy * head * 0.55, y: back.y - ux * head * 0.55)

        context.move(to: start)
        context.addLine(to: neck)
        context.strokePath()

        context.move(to: end)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.setLineWidth(width * 0.5)
        context.drawPath(using: .fillStroke)
    }

    private static func pixelate(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(10, CGFloat(image.width) / 70), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return ciContext.createCGImage(output, from: input.extent)
    }
}

// Draws the 1024×1024 PopShot icon (graphite). Usage: swift scripts/render-icon.swift out.png
import AppKit

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

/// Apple-style "continuous corner" squircle (superellipse).
func squircle(_ r: NSRect) -> NSBezierPath {
    let p = NSBezierPath(); let n = 5.0; let steps = 400
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1), y = pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        let pt = NSPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close(); return p
}

struct Style { let bg: [NSColor]; let corners: NSColor; let sky: [NSColor]; let mountain: [NSColor]; let back: NSColor; let sun: NSColor; let highlight: CGFloat }

func draw(_ s: Style, in ctx: CGContext, origin: NSPoint) {
    ctx.saveGState(); ctx.translateBy(x: origin.x, y: origin.y)
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = squircle(body)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = c(0, 0.35); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -14); sh.set()
    s.bg[1].setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: s.bg)!.draw(in: path, angle: -90)
    // soft top sheen
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    NSGradient(colors: [c(0xFFFFFF, s.highlight), c(0xFFFFFF, 0)])!.draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // viewfinder corners
    let f = body.insetBy(dx: 168, dy: 168); let arm: CGFloat = 112
    let k = NSBezierPath(); k.lineWidth = 38; k.lineCapStyle = .round; k.lineJoinStyle = .round
    for (x, y, dx, dy) in [(f.minX, f.minY, 1.0, 1.0), (f.maxX, f.minY, -1.0, 1.0), (f.minX, f.maxY, 1.0, -1.0), (f.maxX, f.maxY, -1.0, -1.0)] {
        k.move(to: NSPoint(x: x, y: y + dy * arm)); k.line(to: NSPoint(x: x, y: y)); k.line(to: NSPoint(x: x + dx * arm, y: y))
    }
    s.corners.setStroke(); k.stroke()

    // the photo, lifted and popping up out of the frame
    let card = NSRect(x: 512 - 190, y: 512 - 120 + 34, width: 380, height: 270)
    NSGraphicsContext.saveGraphicsState()
    let cs = NSShadow(); cs.shadowColor = c(0, 0.32); cs.shadowBlurRadius = 40; cs.shadowOffset = NSSize(width: 0, height: -22); cs.set()
    s.back.setFill(); NSBezierPath(roundedRect: card, xRadius: 42, yRadius: 42).fill()
    NSGraphicsContext.restoreGraphicsState()
    let pic = card.insetBy(dx: 22, dy: 22)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: pic, xRadius: 24, yRadius: 24).addClip()
    NSGradient(colors: s.sky)!.draw(in: pic, angle: -90)
    s.sun.setFill(); NSBezierPath(ovalIn: NSRect(x: pic.maxX - 110, y: pic.maxY - 96, width: 58, height: 58)).fill()
    let m = NSBezierPath()
    m.move(to: NSPoint(x: pic.minX - 10, y: pic.minY))
    m.curve(to: NSPoint(x: pic.minX + 110, y: pic.minY + 130), controlPoint1: NSPoint(x: pic.minX + 40, y: pic.minY + 60), controlPoint2: NSPoint(x: pic.minX + 80, y: pic.minY + 130))
    m.curve(to: NSPoint(x: pic.minX + 210, y: pic.minY + 60), controlPoint1: NSPoint(x: pic.minX + 150, y: pic.minY + 130), controlPoint2: NSPoint(x: pic.minX + 175, y: pic.minY + 70))
    m.curve(to: NSPoint(x: pic.maxX + 10, y: pic.minY + 100), controlPoint1: NSPoint(x: pic.minX + 250, y: pic.minY + 50), controlPoint2: NSPoint(x: pic.maxX - 40, y: pic.minY + 100))
    m.line(to: NSPoint(x: pic.maxX + 10, y: pic.minY - 10)); m.line(to: NSPoint(x: pic.minX - 10, y: pic.minY - 10)); m.close()
    NSGradient(colors: s.mountain)!.draw(in: m, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

let graphite = Style(bg: [c(0x4A4A4F), c(0x1C1C1E)], corners: c(0xFFFFFF, 0.9), sky: [c(0x8EC5FF), c(0xFFD6A5)],
                     mountain: [c(0x5E5CE6), c(0x2B2A8C)], back: .white, sun: c(0xFF9F0A), highlight: 0.12)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
draw(graphite, in: NSGraphicsContext.current!.cgContext, origin: .zero)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

import AppKit
import Combine
import SwiftUI

struct Canvas: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> CanvasView { CanvasView(model: model) }
    func updateNSView(_ view: CanvasView, context: Context) { view.needsDisplay = true }
}

/// The drawing surface. Mouse input becomes annotations in image-pixel coordinates.
final class CanvasView: NSView, NSTextFieldDelegate {
    private enum Drag {
        case shape(start: CGPoint, end: CGPoint)
        case pen([CGPoint])
        case crop(start: CGPoint, end: CGPoint)
        case move(original: Annotation, start: CGPoint, moved: Bool)
    }

    private let model: EditorModel
    private var observation: AnyCancellable?
    private var drag: Drag?
    private var textField: NSTextField?
    private var textAnchor = CGPoint.zero
    private var editingTextID: UUID?

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
        }
        model.commitPendingText = { [weak self] in self?.commitText() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: model.tool == .select ? .arrow : (model.tool == .text ? .iBeam : .crosshair))
    }

    // MARK: Geometry

    private var imageSize: CGSize { model.renderer.size }

    private var imageRect: CGRect {
        let area = bounds.insetBy(dx: 12, dy: 12)
        guard imageSize.width > 0, imageSize.height > 0, area.width > 0, area.height > 0 else { return .zero }
        let scale = min(area.width / imageSize.width, area.height / imageSize.height)
        let width = imageSize.width * scale, height = imageSize.height * scale
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    private var scale: CGFloat { max(imageRect.width / max(imageSize.width, 1), 0.0001) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let r = imageRect
        let x = (p.x - r.minX) / scale, y = (p.y - r.minY) / scale
        return CGPoint(x: min(max(x, 0), imageSize.width), y: min(max(y, 0), imageSize.height))
    }

    private func viewPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + p.x * scale, y: imageRect.minY + p.y * scale)
    }

    private func viewRect(_ r: CGRect) -> CGRect {
        let origin = viewPoint(r.origin)
        return CGRect(x: origin.x, y: origin.y, width: r.width * scale, height: r.height * scale)
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, imageRect.width > 0 else { return }

        context.saveGState()
        context.translateBy(x: imageRect.minX, y: imageRect.minY)
        context.scaleBy(x: scale, y: scale)
        context.clip(to: CGRect(origin: .zero, size: imageSize))
        context.interpolationQuality = .high
        var annotations = model.state.annotations.filter { $0.id != editingTextID }
        if let draft = draftAnnotation { annotations.append(draft) }
        model.renderer.drawScene(in: context, annotations: annotations)
        context.restoreGState()

        drawCropOverlay(in: context)
        drawSelection(in: context)
    }

    private var draftAnnotation: Annotation? {
        switch drag {
        case let .shape(start, end)?: return shapeAnnotation(from: start, to: end)
        case let .pen(points)? where points.count > 1: return model.makeAnnotation(.pen(points))
        default: return nil
        }
    }

    private func shapeAnnotation(from start: CGPoint, to end: CGPoint) -> Annotation? {
        let rect = Self.rect(start, end)
        switch model.tool {
        case .arrow: return model.makeAnnotation(.arrow(start, end))
        case .rect: return model.makeAnnotation(.rect(rect))
        case .highlight: return model.makeAnnotation(.highlight(rect))
        case .blur: return model.makeAnnotation(.blur(rect))
        default: return nil
        }
    }

    private func drawCropOverlay(in context: CGContext) {
        let crop: CGRect?
        if case let .crop(start, end)? = drag { crop = Self.rect(start, end) } else { crop = model.state.crop }
        guard let crop else { return }
        let cropRect = viewRect(crop)
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.addRect(imageRect)
        context.addRect(cropRect)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.stroke(cropRect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
    }

    private func drawSelection(in context: CGContext) {
        guard model.tool == .select, let id = model.selection, let annotation = model.annotation(id) else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(viewRect(annotation.bounds).insetBy(dx: -4, dy: -4))
        context.restoreGState()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(nil)
        let point = imagePoint(event)
        let tolerance = 6 / scale

        // Double-click closes the editor and keeps the edits, mirroring double-click to open it.
        // Not with Text or Crop (a click there types or clears the crop), and not on a text mark,
        // where double-click means "edit this text".
        if event.clickCount == 2, model.tool != .text, model.tool != .crop,
           !(model.tool == .select && model.hit(point, tolerance: tolerance)?.text != nil) {
            drag = nil
            DispatchQueue.main.async { [model] in model.requestDone?() }
            return
        }

        switch model.tool {
        case .select:
            guard let hit = model.hit(point, tolerance: tolerance) else {
                model.selection = nil
                return
            }
            model.selection = hit.id
            if event.clickCount == 2, case let .text(origin, _) = hit.shape {
                beginText(at: origin, editing: hit)
            } else {
                drag = .move(original: hit, start: point, moved: false)
            }
        case .text:
            if let hit = model.hit(point, tolerance: tolerance), case let .text(origin, _) = hit.shape {
                beginText(at: origin, editing: hit)
            } else {
                beginText(at: point)
            }
        case .pen:
            drag = .pen([point])
        case .crop:
            drag = .crop(start: point, end: point)
        case .arrow, .rect, .highlight, .blur:
            drag = .shape(start: point, end: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(with: event)
    }

    private func updateDrag(with event: NSEvent) {
        let point = imagePoint(event)
        switch drag {
        case let .shape(start, _)?:
            let end = event.modifierFlags.contains(.shift) ? constrained(start, point) : point
            drag = .shape(start: start, end: end)
        case var .pen(points)?:
            points.append(point)
            drag = .pen(points)
        case let .crop(start, _)?:
            drag = .crop(start: start, end: point)
        case let .move(original, start, moved)?:
            if !moved { model.checkpoint() }
            model.replace(original.offset(by: CGSize(width: point.x - start.x, height: point.y - start.y)))
            drag = .move(original: original, start: start, moved: true)
        case nil:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        updateDrag(with: event) // the pointer can move between the last drag event and release
        defer {
            drag = nil
            needsDisplay = true
        }
        let minimum = 3 / scale
        switch drag {
        case let .shape(start, end)?:
            guard hypot(end.x - start.x, end.y - start.y) > minimum,
                  let annotation = shapeAnnotation(from: start, to: end) else { return }
            model.add(annotation)
        case let .pen(points)? where points.count > 1:
            model.add(model.makeAnnotation(.pen(points)))
        case let .crop(start, end)?:
            let rect = Self.rect(start, end)
            if rect.width > minimum * 4, rect.height > minimum * 4 {
                model.setCrop(rect)
            } else if model.state.crop != nil {
                model.setCrop(nil) // a plain click clears the crop
            }
        default:
            break
        }
    }

    /// Shift: arrows snap to 45°, boxes become squares.
    private func constrained(_ start: CGPoint, _ point: CGPoint) -> CGPoint {
        let dx = point.x - start.x, dy = point.y - start.y
        if model.tool == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }

    // MARK: Text

    private func beginText(at point: CGPoint, editing existing: Annotation? = nil) {
        commitText()
        let fontSize = (existing?.fontSize ?? model.fontSize) * scale
        let field = NSTextField(string: existing?.text ?? "")
        field.font = Annotation.font(size: fontSize)
        field.textColor = existing?.color ?? model.color
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Type, then press Return"
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self

        let origin = viewPoint(point)
        field.frame = NSRect(x: origin.x - 2, y: origin.y - 1,
                             width: max(220, bounds.maxX - origin.x - 8), height: ceil(fontSize * 1.3) + 4)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textAnchor = point
        editingTextID = existing?.id
        needsDisplay = true
    }

    func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let editingID = editingTextID
        editingTextID = nil
        field.removeFromSuperview()

        if let id = editingID, var existing = model.annotation(id) {
            if text.isEmpty {
                model.remove(id)
            } else if existing.text != text, case let .text(origin, _) = existing.shape {
                existing.shape = .text(origin, text)
                model.update(existing)
            }
        } else if !text.isEmpty {
            model.add(model.makeAnnotation(.text(textAnchor, text)))
        }
        needsDisplay = true
    }

    private func cancelText() {
        guard let field = textField else { return }
        textField = nil
        editingTextID = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitText()
            window?.makeFirstResponder(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelText()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitText()
    }
}

import AppKit

/// `PopShot --self-test <image> [output.png]` runs detection, the editor renderer and OCR
/// without any UI, which makes the core logic easy to check from a terminal or CI.
enum SelfTest {
    static func run(_ arguments: [String]) -> Never {
        guard let input = arguments.first else {
            print("usage: PopShot --self-test <image> [output.png]")
            exit(2)
        }
        let url = URL(fileURLWithPath: input)
        print("screen-capture attribute:", CaptureClassifier.isMarkedAsScreenCapture(url))
        print("system capture name:", CaptureClassifier.hasSystemCaptureName(url.lastPathComponent))
        print("classified as:", CaptureClassifier.classify(url, notBefore: .distantPast).map { "\($0)" } ?? "not a capture")

        guard let loaded = ImageFiles.load(url) else {
            print("FAIL: could not load image")
            exit(1)
        }
        let w = CGFloat(loaded.image.width), h = CGFloat(loaded.image.height)
        print("loaded: \(loaded.image.width)×\(loaded.image.height) @\(loaded.pixelsPerPoint)x")

        let editor = EditorModel(image: loaded.image, pixelsPerPoint: loaded.pixelsPerPoint)
        editor.add(editor.makeAnnotation(.arrow(CGPoint(x: w * 0.1, y: h * 0.1), CGPoint(x: w * 0.4, y: h * 0.4))))
        editor.add(editor.makeAnnotation(.rect(CGRect(x: w * 0.5, y: h * 0.1, width: w * 0.3, height: h * 0.2))))
        editor.add(editor.makeAnnotation(.highlight(CGRect(x: w * 0.1, y: h * 0.6, width: w * 0.3, height: h * 0.08))))
        editor.add(editor.makeAnnotation(.blur(CGRect(x: w * 0.02, y: h * 0.28, width: w * 0.6, height: h * 0.16))))
        editor.add(editor.makeAnnotation(.pen([CGPoint(x: w * 0.2, y: h * 0.8), CGPoint(x: w * 0.3, y: h * 0.85), CGPoint(x: w * 0.4, y: h * 0.8)])))
        editor.add(editor.makeAnnotation(.text(CGPoint(x: w * 0.12, y: h * 0.45), "PopShot self-test")))
        editor.undo()
        editor.redo()
        editor.setCrop(CGRect(x: w * 0.05, y: h * 0.05, width: w * 0.9, height: h * 0.9))

        guard let rendered = editor.render() else {
            print("FAIL: render failed")
            exit(1)
        }
        let expected = CGRect(x: w * 0.05, y: h * 0.05, width: w * 0.9, height: h * 0.9).integral
        print("rendered: \(rendered.width)×\(rendered.height) (expected \(Int(expected.width))×\(Int(expected.height)))")
        guard rendered.width == Int(expected.width), rendered.height == Int(expected.height) else {
            print("FAIL: crop size mismatch")
            exit(1)
        }

        if arguments.count > 1 {
            let output = URL(fileURLWithPath: arguments[1])
            do {
                try ImageFiles.write(rendered, to: output, pixelsPerPoint: loaded.pixelsPerPoint)
                print("wrote:", output.path)
            } catch {
                print("FAIL: write failed: \(error)")
                exit(1)
            }
        }

        let text = OCR.recognizeText(in: loaded.image)
        print("ocr original: \(text.split(separator: "\n").count) lines; first: \(text.split(separator: "\n").first ?? "—")")
        let blurredText = OCR.recognizeText(in: rendered)
        print("ocr rendered: \(blurredText.split(separator: "\n").joined(separator: " | "))")
        if text.contains("Invoice") && blurredText.contains("Invoice") {
            print("FAIL: blurred text is still readable")
            exit(1)
        }

        let snapshot = arguments.count > 1
            ? URL(fileURLWithPath: arguments[1]).deletingPathExtension().appendingPathExtension("canvas.png")
            : nil
        testCanvas(loaded, snapshot: snapshot)
        print("OK")
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }

    /// Drives the real canvas with mouse events and checks where annotations land in image pixels.
    private static func testCanvas(_ loaded: ImageFiles.Loaded, snapshot: URL?) {
        _ = NSApplication.shared
        let editor = EditorModel(image: loaded.image, pixelsPerPoint: loaded.pixelsPerPoint)
        // Half the image size plus the canvas's 12 pt inset → scale 0.5 with the image at (12, 12).
        let frame = NSRect(x: 0, y: 0, width: CGFloat(loaded.image.width) / 2 + 24, height: CGFloat(loaded.image.height) / 2 + 24)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let canvas = CanvasView(model: editor)
        window.contentView = canvas

        func drag(_ points: [CGPoint]) {
            for (index, point) in points.enumerated() {
                let type: NSEvent.EventType = index == 0 ? .leftMouseDown
                    : index == points.count - 1 ? .leftMouseUp : .leftMouseDragged
                guard let event = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                                                     timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                     eventNumber: 0, clickCount: 1, pressure: 1) else { fail("event") }
                switch type {
                case .leftMouseDown: canvas.mouseDown(with: event)
                case .leftMouseUp: canvas.mouseUp(with: event)
                default: canvas.mouseDragged(with: event)
                }
            }
        }
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1 && abs(a.y - b.y) < 1 }
        let w = CGFloat(loaded.image.width), h = CGFloat(loaded.image.height)
        /// A point at a fraction of the image, in canvas (view) coordinates…
        func view(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: 12 + fx * w / 2, y: 12 + fy * h / 2) }
        /// …and the image pixel it should map to.
        func pixel(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: fx * w, y: fy * h) }

        editor.choose(.arrow)
        drag([view(0.1, 0.1), view(0.2, 0.2), view(0.3, 0.3)])
        guard case let .arrow(start, end)? = editor.state.annotations.last?.shape,
              near(start, pixel(0.1, 0.1)), near(end, pixel(0.3, 0.3))
        else { fail("arrow mapped wrongly: \(String(describing: editor.state.annotations.last?.shape))") }

        // Select the arrow, move it 10 pt (20 px at this scale), then undo the move.
        editor.choose(.select)
        let grab = view(0.2, 0.2)
        drag([grab, CGPoint(x: grab.x + 5, y: grab.y + 5), CGPoint(x: grab.x + 10, y: grab.y + 10)])
        guard case let .arrow(moved, _)? = editor.state.annotations.last?.shape,
              near(moved, CGPoint(x: start.x + 20, y: start.y + 20))
        else { fail("move landed wrongly: \(String(describing: editor.state.annotations.last?.shape))") }
        editor.undo()
        guard case let .arrow(restored, _)? = editor.state.annotations.last?.shape, near(restored, start)
        else { fail("undo of move") }

        editor.choose(.rect)
        drag([view(0.5, 0.1), view(0.6, 0.15), view(0.75, 0.3)])
        guard case let .rect(box)? = editor.state.annotations.last?.shape,
              near(box.origin, pixel(0.5, 0.1)), near(CGPoint(x: box.maxX, y: box.maxY), pixel(0.75, 0.3))
        else { fail("rect mapped wrongly") }

        // Text: click, type, press Return.
        editor.choose(.text)
        drag([view(0.1, 0.6)])
        guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first else { fail("no text box") }
        field.stringValue = "Typed in the canvas"
        canvas.commitText()
        guard editor.state.annotations.last?.text == "Typed in the canvas" else { fail("text not committed") }

        editor.choose(.crop)
        drag([view(0.05, 0.05), view(0.5, 0.5), view(0.9, 0.85)])
        guard let crop = editor.state.crop, near(crop.origin, pixel(0.05, 0.05)),
              near(CGPoint(x: crop.maxX, y: crop.maxY), pixel(0.9, 0.85))
        else { fail("crop mapped wrongly: \(String(describing: editor.state.crop))") }

        if let snapshot, let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: snapshot)
            print("canvas snapshot:", snapshot.path)
        }
        print("canvas: arrow, move, undo, rect, text and crop land on the right pixels")
    }
}

import AppKit
import Combine

final class EditorModel: ObservableObject {
    let renderer: SceneRenderer
    let pixelsPerPoint: CGFloat

    @Published private(set) var state = EditState()
    @Published private(set) var tool: Tool = .arrow
    @Published private(set) var color = Palette.colors[0]
    @Published private(set) var widthIndex = 1
    @Published var selection: UUID?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [EditState] = [] { didSet { canUndo = !undoStack.isEmpty } }
    private var redoStack: [EditState] = [] { didSet { canRedo = !redoStack.isEmpty } }

    /// Set by the canvas: commits a text box that's still being typed in.
    var commitPendingText: (() -> Void)?
    /// Set by the pop-up: finish editing (double-click on the canvas).
    var requestDone: (() -> Void)?

    init(image: CGImage, pixelsPerPoint: CGFloat) {
        renderer = SceneRenderer(base: image)
        self.pixelsPerPoint = pixelsPerPoint
    }

    var strokeWidth: CGFloat { Palette.strokeWidths[widthIndex] * pixelsPerPoint }
    var fontSize: CGFloat { Palette.fontSizes[widthIndex] * pixelsPerPoint }
    var hasChanges: Bool { state != EditState() }

    func makeAnnotation(_ shape: Annotation.Shape) -> Annotation {
        Annotation(shape: shape, color: color, width: strokeWidth, fontSize: fontSize)
    }

    func annotation(_ id: UUID) -> Annotation? {
        state.annotations.first { $0.id == id }
    }

    /// Topmost annotation under `point`.
    func hit(_ point: CGPoint, tolerance: CGFloat) -> Annotation? {
        state.annotations.last { $0.contains(point, tolerance: tolerance) }
    }

    func choose(_ tool: Tool) {
        commitPendingText?()
        self.tool = tool
        if tool != .select { selection = nil }
    }

    func setColor(_ color: NSColor) {
        self.color = color
        modifySelection { $0.color = color }
    }

    func setWidth(_ index: Int) {
        widthIndex = index
        let width = strokeWidth, size = fontSize
        modifySelection {
            $0.width = width
            $0.fontSize = size
        }
    }

    // MARK: Edits (each one is a single undo step)

    func checkpoint() {
        undoStack.append(state)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func add(_ annotation: Annotation) {
        checkpoint()
        state.annotations.append(annotation)
    }

    func update(_ annotation: Annotation) {
        checkpoint()
        replace(annotation)
    }

    /// Changes an annotation without recording undo (used while dragging; call `checkpoint()` first).
    func replace(_ annotation: Annotation) {
        guard let index = state.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        state.annotations[index] = annotation
    }

    func remove(_ id: UUID) {
        checkpoint()
        state.annotations.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    func setCrop(_ rect: CGRect?) {
        checkpoint()
        state.crop = rect
    }

    func undo() {
        commitPendingText?()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
        selection = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
        selection = nil
    }

    func render() -> CGImage? {
        commitPendingText?()
        return renderer.export(state: state)
    }

    private func modifySelection(_ change: (inout Annotation) -> Void) {
        guard let id = selection, var annotation = annotation(id) else { return }
        change(&annotation)
        update(annotation)
    }
}

import AppKit
import AVKit
import SwiftUI

struct PopupRootView: View {
    @ObservedObject var model: PopupModel
    let controller: PopupController
    @StateObject private var tips = HoverTip()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let editor = model.editor {
                    EditorToolbar(editor: editor, controller: controller)
                } else {
                    ViewerToolbar(model: model, controller: controller)
                }
            }
            .frame(height: 48)
            .padding(.horizontal, 10)

            Divider().opacity(0.6)

            if let editor = model.editor {
                Canvas(model: editor)
            } else if let video = model.video {
                PlayerView(model: video).padding(8)
            } else {
                ImagePreview(image: model.image) { controller.edit() }
                    .help("Double-click to edit")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(HoverTipLayer(tips: tips))
        .coordinateSpace(name: HoverTip.coordinateSpace)
        .environmentObject(tips)
        .background(VisualEffectBackground())
        .ignoresSafeArea()
    }
}

private struct ViewerToolbar: View {
    @ObservedObject var model: PopupModel
    let controller: PopupController

    var body: some View {
        HStack(spacing: 2) {
            ToolbarIcon(symbol: "xmark", help: "Close (Esc)") { controller.close() }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.capture.url.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            Spacer(minLength: 8)

            if model.capture.kind == .image {
                ToolbarIcon(symbol: "doc.on.doc", help: "Copy (⌘C)") { controller.copyCapture() }
                ToolbarIcon(symbol: "text.viewfinder", help: "Copy text in image (⌘⇧C)") { controller.copyText() }
                ToolbarIcon(symbol: "pencil.tip.crop.circle", help: "Edit (E)") { controller.edit() }
                ToolbarIcon(symbol: "pin", help: "Pin on top of all windows (P)") { controller.pin() }
            } else {
                ToolbarIcon(symbol: "doc.on.doc", help: "Copy video file (⌘C)") { controller.copyCapture() }
                ToolbarIcon(symbol: "scissors", help: "Trim (T)") { controller.trim() }
            }
            ShareLink(item: model.capture.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip("Share")
            ToolbarIcon(symbol: "folder", help: "Show in Finder (⌘R)") { controller.reveal() }
            ToolbarIcon(symbol: "arrow.up.forward.app", help: "Open in default app (⌘O)") { controller.openInDefaultApp() }
            ToolbarIcon(symbol: "square.and.arrow.down", help: "Save as… (⌘S)") { controller.saveAs() }
            ToolbarIcon(symbol: "trash", help: "Move to Trash (⌫)") { controller.trash() }
        }
    }
}

private struct EditorToolbar: View {
    @ObservedObject var editor: EditorModel
    let controller: PopupController

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                ToolbarIcon(symbol: tool.symbol, help: tool.help, isOn: editor.tool == tool) { editor.choose(tool) }
            }
            separator
            ForEach(Palette.colors.indices, id: \.self) { index in
                let color = Palette.colors[index]
                Button { editor.setColor(color) } label: {
                    Circle()
                        .fill(Color(nsColor: color))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(editor.color == color ? 1 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip("Color")
            }
            separator
            ForEach(Palette.strokeWidths.indices, id: \.self) { index in
                Button { editor.setWidth(index) } label: {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 14, height: Palette.strokeWidths[index])
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(editor.widthIndex == index ? Color.primary.opacity(0.12) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip(["Thin", "Medium", "Thick"][index])
            }
            separator
            ToolbarIcon(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { editor.undo() }
                .disabled(!editor.canUndo)
            ToolbarIcon(symbol: "arrow.uturn.forward", help: "Redo (⌘⇧Z)") { editor.redo() }
                .disabled(!editor.canRedo)

            Spacer(minLength: 8)

            Button("Cancel") { controller.cancelEdit() }.tip("Discard changes (Esc)")
            Button("Copy") { controller.copyEdited() }.tip("Copy the edited image (⌘C)")
            Button("Save Copy") { controller.saveEditedCopy() }.tip("Save as a new file (⌘S)")
            Button("Done") { controller.finishEdit() }
                .buttonStyle(.borderedProminent)
                .tip("Save changes to the original (⌘Return)")
        }
    }

    private var separator: some View {
        Divider().frame(height: 20).padding(.horizontal, 4)
    }
}

struct ToolbarIcon: View {
    let symbol: String
    let help: String
    var isOn = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .background(RoundedRectangle(cornerRadius: 6).fill(background))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .tip(help)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isOn { return Color.accentColor.opacity(0.18) }
        return hovering && isEnabled ? Color.primary.opacity(0.1) : .clear
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct PlayerView: NSViewRepresentable {
    let model: VideoModel

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = model.player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        model.playerView = view
        model.player.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

struct ImagePreview: NSViewRepresentable {
    let image: NSImage?
    var onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> ImagePreviewView { ImagePreviewView() }

    func updateNSView(_ view: ImagePreviewView, context: Context) {
        view.image = image
        view.onDoubleClick = onDoubleClick
    }
}

/// Shows the capture with a soft shadow; double-click opens the editor.
/// (Drag-out to other apps was removed for v0.1.)
final class ImagePreviewView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var onDoubleClick: (() -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var imageRect: NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let area = bounds.insetBy(dx: 12, dy: 12)
        let scale = min(area.width / image.size.width, area.height / image.size.height, 2)
        let width = image.size.width * scale, height = image.size.height * scale
        return NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 10
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.set()
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
    }
}

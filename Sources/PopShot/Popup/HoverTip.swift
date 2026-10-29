import SwiftUI

/// Toolbar hover labels. The system tooltip waits about a second; these appear after 0.2 s,
/// and once one is showing, sliding to the next button switches the label instantly.
final class HoverTip: ObservableObject {
    static let coordinateSpace = "popup"

    @Published private(set) var text: String?
    @Published private(set) var anchor = CGRect.zero
    private var pending: DispatchWorkItem?
    private var hiddenAt = Date.distantPast

    func hover(_ text: String, over frame: CGRect, inside: Bool) {
        pending?.cancel()
        guard inside else {
            if anchor == frame, self.text != nil {
                self.text = nil
                hiddenAt = Date()
            }
            return
        }
        // Moving straight from one button to the next: no second delay.
        if self.text != nil || Date().timeIntervalSince(hiddenAt) < 0.4 {
            show(text, frame)
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.show(text, frame) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Clicking a button hides its label, like the system tooltip.
    func dismiss() {
        pending?.cancel()
        text = nil
    }

    private func show(_ text: String, _ frame: CGRect) {
        self.text = text
        anchor = frame
    }
}

private struct HoverTipModifier: ViewModifier {
    let text: String
    @EnvironmentObject private var tips: HoverTip
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { frame = geometry.frame(in: .named(HoverTip.coordinateSpace)) }
                    .onChange(of: geometry.frame(in: .named(HoverTip.coordinateSpace))) { frame = $0 }
            })
            .onHover { tips.hover(text, over: frame, inside: $0) }
            .simultaneousGesture(TapGesture().onEnded { tips.dismiss() })
            .accessibilityHint(text)
    }
}

extension View {
    /// A quick hover label shown below the view (inside a `HoverTipLayer`).
    func tip(_ text: String) -> some View {
        modifier(HoverTipModifier(text: text))
    }
}

/// Draws the current label below its button, kept inside the window's edges.
struct HoverTipLayer: View {
    @ObservedObject var tips: HoverTip
    @State private var labelSize = CGSize.zero

    var body: some View {
        GeometryReader { container in
            if let text = tips.text {
                let half = labelSize.width / 2
                let x = min(max(tips.anchor.midX, half + 6), container.size.width - half - 6)
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .fixedSize()
                    .background(GeometryReader { label in
                        Color.clear
                            .onAppear { labelSize = label.size }
                            .onChange(of: label.size) { labelSize = $0 }
                    })
                    .position(x: x, y: tips.anchor.maxY + 6 + labelSize.height / 2)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.1), value: tips.text)
        .allowsHitTesting(false)
    }
}

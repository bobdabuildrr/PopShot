import AppKit
import SwiftUI

/// A regular window hosting SwiftUI. PopShot has no Dock icon, so it activates itself first.
final class HostedWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    /// `chromeless` hides the title bar so the content runs edge to edge, like Apple's welcome screens.
    func show<Content: View>(title: String, chromeless: Bool = false, onClose: (() -> Void)? = nil,
                             content: () -> Content) {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let host = NSHostingView(rootView: content())
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = title
            if chromeless {
                window.styleMask.insert(.fullSizeContentView)
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.delegate = self
            window.center()
            self.window = window
            self.onClose = onClose
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        window = nil
    }
}

enum SettingsWindow {
    private static let window = HostedWindow()

    static func show() {
        window.show(title: "PopShot Settings") { SettingsView() }
    }
}

enum OnboardingWindow {
    private static let window = HostedWindow()
    private static let choices = OnboardingChoices()

    static func show() {
        window.show(title: "Welcome to PopShot", chromeless: true, onClose: finish) {
            OnboardingView(choices: choices) { window.close() }
        }
    }

    /// Runs when the user closes the window (Done or the red close button), but not when
    /// PopShot quits with the window still open; then it shows again next launch.
    private static func finish() {
        guard !Prefs.onboarded, !AppDelegate.isTerminating else { return }
        Prefs.onboarded = true
        ThumbnailSetting.setInstantMode(choices.instant)
        if choices.launchAtLogin != LoginItem.isEnabled { LoginItem.setEnabled(choices.launchAtLogin) }
    }
}

final class OnboardingChoices: ObservableObject {
    @Published var instant = true
    @Published var launchAtLogin = true
}

struct OnboardingView: View {
    @ObservedObject var choices: OnboardingChoices
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .padding(.top, 44)

            Text("Welcome to PopShot")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 18)
            Text("Every screenshot opens the moment you take it.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 20) {
                feature("bolt.fill", .orange, "Opens instantly",
                        "Press ⌘⇧3, ⌘⇧4 or ⌘⇧5 as always. Your capture pops up right away.")
                feature("scribble", .blue, "Copy, mark up, pin",
                        "Draw, blur, crop, copy text, or pin it above your windows.")
                feature("lock.fill", .green, "Private by design",
                        "Everything stays on your Mac. Nothing is ever uploaded.")
            }
            .padding(.top, 32)
            .padding(.horizontal, 48)

            VStack(spacing: 0) {
                settingRow("bolt.fill", .orange, "Instant pop-up",
                           info: "Hides Apple's small thumbnail in the corner after each screenshot. While it shows, macOS waits about 5 seconds before saving, so PopShot can't open your capture yet. It comes back when you quit PopShot.",
                           isOn: $choices.instant)
                Divider().padding(.leading, 52)
                settingRow("power", .green, "Open at login",
                           info: "Starts PopShot automatically when you turn on or log in to your Mac, so it's always ready. It runs quietly in the menu bar and uses almost no memory.",
                           isOn: $choices.launchAtLogin)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .padding(.top, 30)
            .padding(.horizontal, 40)

            Text("If macOS asks whether PopShot can access your Desktop, click Allow. That's where your screenshots are saved.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 52)

            Button(action: done) {
                Text("Continue")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 28)
            .padding(.horizontal, 120)

            Text("Then try it: press ⌘⇧4 and drag.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
                .padding(.bottom, 32)
        }
        .frame(width: 520)
        .background(VisualEffectBackground().ignoresSafeArea())
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// An iOS Settings-style row: a white symbol on a colored rounded square, a label and a switch.
    private func settingRow(_ symbol: String, _ tint: Color, _ title: String, info: String,
                            isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
            Text(title).font(.system(size: 13))
            InfoButton(text: info)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// An ⓘ that explains a setting in a small popover, shown on hover or click.
struct InfoButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover { showing = $0 }
            .onTapGesture { showing.toggle() }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                Text(text)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
                    .padding(12)
            }
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.Key.placement) private var placement = PopupPlacement.center.rawValue
    @AppStorage(Prefs.Key.autoCloseSeconds) private var autoCloseSeconds = 0
    @AppStorage(Prefs.Key.closeOnClickOutside) private var closeOnClickOutside = true
    @AppStorage(Prefs.Key.showForScreenshots) private var showForScreenshots = true
    @AppStorage(Prefs.Key.showForRecordings) private var showForRecordings = true
    @AppStorage(Prefs.Key.autoCopy) private var autoCopy = false
    @AppStorage(Prefs.Key.closeAfterCopy) private var closeAfterCopy = true
    @State private var instant = Prefs.instantMode
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Pop-up") {
                Picker("Position", selection: $placement) {
                    ForEach(PopupPlacement.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Close automatically", selection: $autoCloseSeconds) {
                    Text("Never").tag(0)
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                    Text("After 30 seconds").tag(30)
                }
                Toggle("Close when I click somewhere else", isOn: $closeOnClickOutside)
                Toggle("Open new screenshots", isOn: $showForScreenshots)
                Toggle("Open new screen recordings", isOn: $showForRecordings)
            }

            Section("Clipboard") {
                Toggle("Copy every new capture to the clipboard", isOn: $autoCopy)
                Toggle("Close the pop-up after copying", isOn: $closeAfterCopy)
            }

            Section {
                Toggle("Instant pop-up", isOn: $instant)
                    .onChange(of: instant) { ThumbnailSetting.setInstantMode($0) }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LoginItem.setEnabled($0) }
                LabeledContent("Watching") {
                    HStack {
                        Text(CaptureCenter.shared.folderDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Show") {
                            if let folder = CaptureCenter.shared.folder { NSWorkspace.shared.open(folder) }
                        }
                    }
                }
            } header: {
                Text("System")
            } footer: {
                Text("Instant pop-up hides Apple's floating thumbnail, which otherwise delays every capture by about 5 seconds. PopShot puts it back when you quit. To change where captures are saved, press ⌘⇧5 › Options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("PopShot \(AppInfo.version)")
                    Spacer()
                    Link("GitHub", destination: AppInfo.repoURL)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

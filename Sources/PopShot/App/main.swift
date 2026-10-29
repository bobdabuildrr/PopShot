import AppKit

if let index = CommandLine.arguments.firstIndex(of: "--self-test") {
    SelfTest.run(Array(CommandLine.arguments.dropFirst(index + 1)))
}

// Only one PopShot at a time (e.g. a login item plus a copy you opened by hand); otherwise
// every capture would open twice.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: "app.popshot.PopShot")
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    print("PopShot is already running (pid \(others[0].processIdentifier)).")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

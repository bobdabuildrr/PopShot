import Foundation
import os

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/bobdabuildrr/PopShot")!

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// A new GitHub issue using the bug form, with the PopShot and macOS versions filled in.
    static var bugReportURL: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var components = URLComponents(url: repoURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "macos", value: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
        ]
        return components.url!
    }
}

enum Log {
    private static let logger = Logger(subsystem: "app.popshot.PopShot", category: "app")
    /// `POPSHOT_DEBUG=1` (set by `make run`) mirrors logs to the terminal.
    private static let echo = ProcessInfo.processInfo.environment["POPSHOT_DEBUG"] != nil

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)") // notice level is kept, so `log show` can read it
        if echo { FileHandle.standardError.write(Data("[PopShot] \(message)\n".utf8)) }
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        if echo { FileHandle.standardError.write(Data("[PopShot] ERROR \(message)\n".utf8)) }
    }
}

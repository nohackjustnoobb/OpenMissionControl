//
//  LaunchAtLoginManager.swift
//  OpenMissionControl
//
//  Created by Travis XU on 15/3/2026.
//

import Foundation

enum LaunchAtLoginManager {
    // MARK: - Public API

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func enable() throws {
        let plist = buildPlist()
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        try launchctl("load", "-w", plistURL.path)
    }

    static func disable() throws {
        if isEnabled {
            try launchctl("unload", "-w", plistURL.path)
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    // MARK: - Internals

    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "dev.travisxu.OpenMissionControl"
    }

    private static var executablePath: String {
        Bundle.main.executablePath ?? ""
    }

    private static var launchAgentsURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    private static var plistURL: URL {
        launchAgentsURL.appendingPathComponent("\(bundleID).plist")
    }

    private static func buildPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(bundleID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
    }

    @discardableResult
    private static func launchctl(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

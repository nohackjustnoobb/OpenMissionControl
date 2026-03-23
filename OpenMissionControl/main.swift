//
//  main.swift
//  OpenMissionControl
//
//  Created by Travis XU on 13/3/2026.
//

import AppKit

let bundleIdentifier = Bundle.main.bundleIdentifier ?? "dev.travisxu.OpenMissionControl"
let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
let currentPID = ProcessInfo.processInfo.processIdentifier

if let existingApp = runningApps.first(where: { $0.processIdentifier != currentPID }) {
    existingApp.activate(options: [.activateIgnoringOtherApps])
    exit(0)
}

MainActor.assumeIsolated {
    let appDelegate = AppDelegate()
    NSApplication.shared.delegate = appDelegate
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

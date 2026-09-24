//
//  main.swift
//  OpenMissionControl
//
//  Created by Travis XU on 13/3/2026.
//

import AppKit

let bundleIdentifier = "dev.travisxu.OpenMissionControl"
let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
let currentPID = ProcessInfo.processInfo.processIdentifier
let existingApps = runningApps.filter { $0.processIdentifier != currentPID }

func waitForTermination(of applications: [NSRunningApplication], timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)

    while applications.contains(where: { !$0.isTerminated }), Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
}

if !existingApps.isEmpty {
    existingApps.forEach { $0.terminate() }
    waitForTermination(of: existingApps, timeout: 1.5)

    let remainingApps = existingApps.filter { !$0.isTerminated }
    remainingApps.forEach { $0.forceTerminate() }
    waitForTermination(of: remainingApps, timeout: 0.5)
}

MainActor.assumeIsolated {
    let appDelegate = AppDelegate(openSettingsOnLaunch: !existingApps.isEmpty)
    NSApplication.shared.delegate = appDelegate
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

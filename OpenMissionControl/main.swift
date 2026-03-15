//
//  main.swift
//  OpenMissionControl
//
//  Created by Travis XU on 13/3/2026.
//

import AppKit

MainActor.assumeIsolated {
    let appDelegate = AppDelegate()
    NSApplication.shared.delegate = appDelegate
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

//
//  VMAFApp.swift
//  VMAF
//
//  Created by Oliver Dougherty on 3/4/25.
//

import SwiftUI

@main
struct VMAFApp: App {
    @NSApplicationDelegateAdaptor(AppUpdates.self) private var updates

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                if let updater = updates.controller?.updater {
                    CheckForUpdates(updates: updates, updater: updater)
                }
            }
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 500)
        .defaultPosition(.center)
    }
} 

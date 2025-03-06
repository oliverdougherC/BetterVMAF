//
//  VMAFApp.swift
//  VMAF
//
//  Created by Oliver Dougherty on 3/4/25.
//

import SwiftUI

@main
struct VMAFApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 500)
        .defaultPosition(.center)
    }
} 

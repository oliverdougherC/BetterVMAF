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
            VMAFView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
} 

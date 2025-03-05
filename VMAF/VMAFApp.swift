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
                .frame(width: 500, height: 450)
                .navigationViewStyle(.automatic)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 450)
    }
} 

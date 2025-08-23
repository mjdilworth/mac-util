//
//  ServiceControllerApp.swift
//  Dilly
//
//  Created by Michael Dilworth on 23/08/2025.
//


import SwiftUI


struct ServiceControllerApp: App {
    @State private var showWindow = false

    var body: some Scene {
        // Menu bar item
        MenuBarExtra("ServiceCtl", systemImage: "gearshape") {
            Button("Open Window") {
                showWindow = true
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        // Window for controls
        WindowGroup {
            if showWindow {
                ContentView(showWindow: $showWindow)
            } else {
                EmptyView()
            }
        }
    }
}

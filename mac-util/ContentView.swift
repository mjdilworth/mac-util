import SwiftUI
import Foundation
import AppKit

// Class to monitor display changes
class DisplayMonitor: ObservableObject {
    @Published var displayMessage: String = ""
    private var previousScreens: [NSScreen] = []
    
    init() {
        // Save initial screen information
        previousScreens = NSScreen.screens
        
        // Register for screen change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func screenParametersDidChange() {
        let currentScreens = NSScreen.screens
        
        // Check for connected or disconnected displays
        if currentScreens.count > previousScreens.count {
            // Display connected
            let newScreens = findNewScreens(currentScreens: currentScreens)
            let details = getScreenDetails(for: newScreens)
            displayMessage = "[\(formattedDate())] Display connected: \(details)"
        } else if currentScreens.count < previousScreens.count {
            // Display disconnected
            displayMessage = "[\(formattedDate())] Display disconnected. Total displays now: \(currentScreens.count)"
        } else {
            // Same number but something changed (resolution, etc.)
            let changedScreens = findChangedScreens(oldScreens: previousScreens, newScreens: currentScreens)
            if !changedScreens.isEmpty {
                let details = getScreenDetails(for: changedScreens)
                displayMessage = "[\(formattedDate())] Display settings changed: \(details)"
            }
        }
        
        // Update previous screens for next comparison
        previousScreens = currentScreens
    }
    
    private func findNewScreens(currentScreens: [NSScreen]) -> [NSScreen] {
        // This is simplified - in a real implementation you would need a better way to identify screens
        if currentScreens.count > previousScreens.count {
            // Just return the last screen as the new one (this is a simplification)
            if let lastScreen = currentScreens.last {
                return [lastScreen]
            }
        }
        return []
    }
    
    private func findChangedScreens(oldScreens: [NSScreen], newScreens: [NSScreen]) -> [NSScreen] {
        // For simplicity, we'll just check the main screen for changes
        // In a real implementation, you would need to track each screen by ID
        if let oldMain = oldScreens.first,
           let newMain = newScreens.first,
           oldMain.frame != newMain.frame {
            return [newMain]
        }
        return []
    }
    
    private func getScreenDetails(for screens: [NSScreen]) -> String {
        var details: [String] = []
        
        for screen in screens {
            let frame = screen.frame
            let colorSpace = screen.colorSpace?.localizedName ?? "Unknown"
            let resolution = "\(Int(frame.width))×\(Int(frame.height))"
            let depth = screen.depth
            let isMain = screen == NSScreen.main ? "Yes" : "No"
            
            details.append("""
            Screen \(isMain == "Yes" ? "(Main)" : ""):
              Resolution: \(resolution)
              Color Space: \(colorSpace)
              Depth: \(depth)
              Scale Factor: \(screen.backingScaleFactor)
            """)
        }
        
        return details.joined(separator: "\n")
    }
    
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

struct ContentView: View {
    @Binding var showWindow: Bool
    @State private var outputText: String = "Output will appear here..."
    @StateObject private var displayMonitor = DisplayMonitor()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Service Controller")
                .font(.title)

            Button("Start Service") {
                let result = runShellCommand("launchctl load /Library/LaunchDaemons/com.example.service.plist")
                outputText = "Starting service...\n\(result)"
            }
            .buttonStyle(.borderedProminent)

            Button("Stop Service") {
                let result = runShellCommand("launchctl unload /Library/LaunchDaemons/com.example.service.plist")
                outputText = "Stopping service...\n\(result)"
            }
            .buttonStyle(.bordered)
            
            // Output text box
            ScrollView {
                Text(outputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 120)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )

            Button("Hide Window") {
                WindowController.shared.hideWindow()
            }
            .padding(.top, 10)
        }
        .frame(width: 400, height: 350)
        .padding()
        .onAppear {
            // Log initial screen info
            let screenDetails = getInitialScreenDetails()
            outputText = "[\(formattedDate())] Application started.\nCurrent displays:\n\(screenDetails)"
        }
        .onReceive(displayMonitor.$displayMessage) { newMessage in
            if !newMessage.isEmpty {
                // Append new messages to the output text
                outputText = "\(outputText)\n\n\(newMessage)"
            }
        }
    }
    
    // Get initial screen details
    private func getInitialScreenDetails() -> String {
        var details: [String] = []
        
        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            let resolution = "\(Int(frame.width))×\(Int(frame.height))"
            let isMain = (screen == NSScreen.main) ? "(Main)" : ""
            
            details.append("Display \(index + 1) \(isMain): \(resolution) @ \(screen.backingScaleFactor)x")
        }
        
        return details.isEmpty ? "No displays detected" : details.joined(separator: "\n")
    }
    
    // Helper function for formatted date
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    // Run shell command with proper privileges and return output
    func runShellCommand(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        
        do {
            try task.run()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "No output"
            
            task.waitUntilExit()
            
            return "Exit code: \(task.terminationStatus)\n\(output)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView(showWindow: .constant(true))
}

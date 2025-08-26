import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine

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
    // Preferences
    @State private var isRunningScript: Bool = false
    @State private var autoRunEnabled: Bool
    @State private var debounceSeconds: Double

    private let defaults = UserDefaults.standard
    private let kAutoRun = "AutoRunEnabled"
    private let kDebounce = "DebounceSeconds"

    init(showWindow: Binding<Bool>) {
        self._showWindow = showWindow
        let defaults = UserDefaults.standard
        let autoRun = defaults.object(forKey: kAutoRun) as? Bool ?? true
        let debounce = defaults.object(forKey: kDebounce) as? Double ?? 1.0
        self._autoRunEnabled = State(initialValue: autoRun)
        self._debounceSeconds = State(initialValue: debounce)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Service Controller")
                .font(.title)

            // Large Auto-Run toggle button
            Button(action: {
                autoRunEnabled.toggle()
                defaults.set(autoRunEnabled, forKey: kAutoRun)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: autoRunEnabled ? "play.circle.fill" : "pause.circle")
                    Text(autoRunEnabled ? "Auto-Run: ON" : "Auto-Run: OFF")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(autoRunEnabled ? .green : .gray)
            .help("Toggle automatic layout application on display change")

            // Manual controls (displayplacer only)
            HStack(spacing: 8) {
                let hasDP = (Bundle.main.url(forAuxiliaryExecutable: "displayplacer") != nil)
                    || ((Bundle.main.resourceURL?.appendingPathComponent("displayplacer").path).map { FileManager.default.isExecutableFile(atPath: $0) } ?? false)
                    || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/displayplacer")
                    || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/displayplacer")
                let hasSaved = (UserDefaults.standard.string(forKey: "DisplayplacerSavedCommand")?.isEmpty == false)
                Button("Capture Now") {
                    (NSApp.delegate as? AppDelegate)?.captureLayout()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasDP)
                Button("Apply Layout") {
                    (NSApp.delegate as? AppDelegate)?.applyLayout()
                }
                .buttonStyle(.bordered)
                .disabled(!(hasDP && hasSaved))
                Button("Dry Run Apply") {
                    if let cmd = (NSApp.delegate as? AppDelegate)?.buildDryRunApplyCommand() {
                        let entry = "[\(formattedDate())] Dry run (apply) command\n\(cmd)"
                        outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                    } else {
                        let entry = "[\(formattedDate())] No saved layout or displayplacer not found"
                        outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!(hasDP && hasSaved))
                Spacer()
            }

            // Debounce and status
            HStack(spacing: 8) {
                Text("Debounce:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Stepper(value: $debounceSeconds, in: 0...10, step: 0.5) {
                    Text(String(format: "%.1f s", debounceSeconds))
                        .font(.callout)
                }
                .onChange(of: debounceSeconds) { _, newValue in
                    defaults.set(newValue, forKey: kDebounce)
                }
                Spacer()
            }

            // Log controls
            HStack {
                Spacer()
                Button("Clear Log") { outputText = "" }
                    .buttonStyle(.bordered)
            }

            // Output text box
            ScrollView {
                Text(outputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 200, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )

            Button("Hide Window") { WindowController.shared.hideWindow() }
                .padding(.top, 10)
        }
        .frame(minWidth: 520, minHeight: 520)
        .padding()
        .onAppear {
            let screenDetails = getInitialScreenDetails()
            outputText = "[\(formattedDate())] Application started.\nCurrent displays:\n\(screenDetails)"
        }
        .onReceive(displayMonitor.$displayMessage
            .debounce(for: .seconds(debounceSeconds), scheduler: RunLoop.main)) { newMessage in
            if !newMessage.isEmpty {
                outputText = outputText.isEmpty ? newMessage : "\(newMessage)\n\n\(outputText)"
                if autoRunEnabled, !isRunningScript {
                    isRunningScript = true
                    DispatchQueue.global(qos: .utility).async {
                        if let res = (NSApp.delegate as? AppDelegate)?.applySavedLayout() {
                            DispatchQueue.main.async {
                                let entry = "[\(formattedDate())] Applied display layout (auto)\nExit code: \(res.code)\n\(res.output)"
                                outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                                isRunningScript = false
                            }
                        } else {
                            DispatchQueue.main.async {
                                let entry = "[\(formattedDate())] Auto-run skipped: no saved layout or displayplacer not found"
                                outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                                isRunningScript = false
                            }
                        }
                    }
                }
            }
        }
        // Listen for capture/apply notifications to log into the message box
        .onReceive(NotificationCenter.default.publisher(for: .displayScriptDidRun)) { note in
            let mode = (note.userInfo?["mode"] as? String) ?? "?"
            let code = (note.userInfo?["code"] as? Int32) ?? -999
            let output = (note.userInfo?["output"] as? String) ?? ""
            let entry = "[\(formattedDate())] \(mode.capitalized) completed (code=\(code))\n\(output)"
            outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
        }
        // Keep in sync with Dock/Menu toggles
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let v = defaults.object(forKey: kAutoRun) as? Bool ?? true
            if v != autoRunEnabled { autoRunEnabled = v }
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
    
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

#Preview {
    ContentView(showWindow: .constant(true))
}

import SwiftUI
import AppKit
import Combine

// A singleton class to manage window visibility
class WindowController: NSObject, ObservableObject {
    static let shared = WindowController()
    var window: NSWindow?
    @Published var isWindowVisible: Bool = false
    
    private override init() {
        super.init()
    }
    
    func createAndShowWindow() {
        if window == nil {
            // Create the hosting controller with our SwiftUI view
            let contentView = ContentView(showWindow: .constant(true))
            let hostingController = NSHostingController(rootView: contentView)
            
            // Create a window and set the content view controller
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Service Controller"
            window.contentViewController = hostingController
            window.center()
            window.setFrameAutosaveName("ServiceControllerWindow")
            window.isReleasedWhenClosed = false
            window.delegate = self
            // Ensure the window can resize but not below the ContentView’s minimum
            window.contentMinSize = NSSize(width: 700, height: 560)
            
            self.window = window
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isWindowVisible = true
    }
    
    func hideWindow() {
        window?.orderOut(nil)
        isWindowVisible = false
    }
    
    func toggleWindow() {
        if let window = window, window.isVisible {
            hideWindow()
        } else {
            createAndShowWindow()
        }
    }
}

// Extension to handle window delegate methods
extension WindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isWindowVisible = false
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // Keys shared with ContentView for coordination
    private let kAutoRun = "AutoRunEnabled"
    private let kSavedCmd = "DisplayplacerSavedCommand"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Show the main window on launch
        DispatchQueue.main.async {
            WindowController.shared.createAndShowWindow()
        }
        
        // Don't show window immediately on app launch for menu bar apps
        // Window can still be shown from the menu bar item
        
        // NOTE: We've disabled the automatic permission request on startup
        // as it can cause issues. The user can use the "Test Apple Events Permission"
        // button in the UI instead.
    }
    
    // Return false to prevent app termination when windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - displayplacer helpers (capture/apply)
    fileprivate func displayplacerURL() -> URL? {
        // Try bundle aux executable
        if let url = Bundle.main.url(forAuxiliaryExecutable: "displayplacer") { return url }
        // Try bundled resource
        if let res = Bundle.main.resourceURL?.appendingPathComponent("displayplacer"), FileManager.default.isExecutableFile(atPath: res.path) { return res }
        // Homebrew paths
        let brewArm = URL(fileURLWithPath: "/opt/homebrew/bin/displayplacer")
        if FileManager.default.isExecutableFile(atPath: brewArm.path) { return brewArm }
        let brewIntel = URL(fileURLWithPath: "/usr/local/bin/displayplacer")
        if FileManager.default.isExecutableFile(atPath: brewIntel.path) { return brewIntel }
        return nil
    }
    
    // Capture current layout and extract the apply command from the end of `displayplacer list` output
    @discardableResult
    func captureWithDisplayplacer() -> (code: Int32, output: String, applyCmd: String?) {
        guard let dp = displayplacerURL() else {
            return (-1, "displayplacer not found in bundle or Homebrew paths", nil)
        }
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = dp
        task.arguments = ["list"]
        do { try task.run() } catch { return (-1, "Failed to run displayplacer: \(error.localizedDescription)", nil) }
        // Add a 10-second timeout so the UI doesn’t wait forever
        var didTimeout = false
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 10)
        timer.setEventHandler {
            if task.isRunning {
                didTimeout = true
                task.terminate()
            }
        }
        timer.resume()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        timer.cancel()
        var out = String(data: data, encoding: .utf8) ?? ""
        if didTimeout {
            out += "\n\n[timeout] displayplacer list terminated after 10s."
        }
        let apply = Self.parseApplyCommand(fromListOutput: out)
        if let apply {
            UserDefaults.standard.set(apply, forKey: kSavedCmd)
        }
        return (task.terminationStatus, out, apply)
    }
    
    static func parseApplyCommand(fromListOutput out: String) -> String? {
        // Find the last occurrence of "displayplacer " and take everything from there to the end
        guard let range = out.range(of: "displayplacer ", options: [.backwards]) else { return nil }
        var cmd = String(out[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Some outputs include backticks or wrapping quotes; normalize whitespace
        // Remove any trailing lines like instructions that don’t belong (heuristic: stop at first empty line after command)
        if let emptyRange = cmd.range(of: "\n\n") { cmd = String(cmd[..<emptyRange.lowerBound]) }
        return cmd
    }
    
    func savedApplyCommand() -> String? {
        return UserDefaults.standard.string(forKey: kSavedCmd)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Build the exact inner shell line we will execute for apply (with full path replacement)
    func buildInnerApplyShellLine() -> String? {
        guard var saved = savedApplyCommand(), let dp = displayplacerURL() else { return nil }
        // Replace leading token "displayplacer" with full path if present at the start
        if let r = saved.range(of: "^\\s*displayplacer\\b", options: .regularExpression) {
            saved.replaceSubrange(r, with: "\"\(dp.path)\"")
        }
        return saved
    }
    
    // Execute the saved apply command
    @discardableResult
    func applySavedLayout() -> (code: Int32, output: String) {
        guard let inner = buildInnerApplyShellLine() else {
            return (-1, "No saved layout or displayplacer not found")
        }
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-f", "-c", inner]
        do { try task.run() } catch { return (-1, "Failed to launch zsh: \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, out)
    }
    
    // Provide Dock menu to quickly toggle Auto-Run and show/hide window
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let defaults = UserDefaults.standard
        let hasDP = (Bundle.main.url(forAuxiliaryExecutable: "displayplacer") != nil)
            || ((Bundle.main.resourceURL?.appendingPathComponent("displayplacer").path).map { FileManager.default.isExecutableFile(atPath: $0) } ?? false)
            || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/displayplacer")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/displayplacer")
        let isOn = defaults.object(forKey: kAutoRun) as? Bool ?? true
        let title = isOn ? "Disable Auto-Run" : "Enable Auto-Run"
        let toggleItem = NSMenuItem(title: title, action: #selector(toggleAutoRunFromDock(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = hasDP
        menu.addItem(toggleItem)
        if !hasDP {
            let infoItem = NSMenuItem(title: "displayplacer not found", action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            menu.addItem(infoItem)
        }
        menu.addItem(NSMenuItem.separator())
        let showHideTitle = WindowController.shared.isWindowVisible ? "Hide Window" : "Show Window"
        let showHideItem = NSMenuItem(title: showHideTitle, action: #selector(toggleWindowFromDock(_:)), keyEquivalent: "")
        showHideItem.target = self
        menu.addItem(showHideItem)
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }
    
    @objc private func toggleAutoRunFromDock(_ sender: Any?) {
        let defaults = UserDefaults.standard
        let current = defaults.object(forKey: kAutoRun) as? Bool ?? true
        defaults.set(!current, forKey: kAutoRun)
    }
    
    @objc private func toggleWindowFromDock(_ sender: Any?) {
        WindowController.shared.toggleWindow()
    }
    
    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
}

@main
struct DillyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowController = WindowController.shared
    // Observe defaults for menu reactivity
    @AppStorage("AutoRunEnabled") private var autoRunEnabled: Bool = true
    
    // Helper functions to check availability of displayplacer and saved commands
    private func hasDisplayplacer() -> Bool {
        return (Bundle.main.url(forAuxiliaryExecutable: "displayplacer") != nil)
            || ((Bundle.main.resourceURL?.appendingPathComponent("displayplacer").path)
                .map { FileManager.default.isExecutableFile(atPath: $0) } ?? false)
            || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/displayplacer")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/displayplacer")
    }
    
    private func hasSavedCommand() -> Bool {
        return (UserDefaults.standard.string(forKey: "DisplayplacerSavedCommand")?.isEmpty == false)
    }
    
    var body: some Scene {
        // Menu bar item with guaranteed system icon
        MenuBarExtra("Display Controller", systemImage: "gearshape") {
            VStack(alignment: .leading, spacing: 5) {
                Button(autoRunEnabled ? "Disable Auto-Run" : "Enable Auto-Run") {
                    autoRunEnabled.toggle()
                }
                .disabled(!hasDisplayplacer())
                
                Divider()
                
                Button("Capture Display Layout") {
                    let res = appDelegate.captureWithDisplayplacer()
                    NotificationCenter.default.post(name: .displayScriptDidRun, object: nil, userInfo: [
                        "mode": "capture",
                        "code": res.code,
                        "output": res.output + (res.applyCmd != nil ? "\n\nSaved apply command:\n\(res.applyCmd!)" : "\n\nNo apply command found in output")
                    ])
                }
                .disabled(!hasDisplayplacer())
                
                Button("Apply Display Layout") {
                    let res = appDelegate.applySavedLayout()
                    NotificationCenter.default.post(name: .displayScriptDidRun, object: nil, userInfo: [
                        "mode": "apply",
                        "code": res.code,
                        "output": res.output
                    ])
                }
                .disabled(!(hasDisplayplacer() && hasSavedCommand()))
                
                Divider()
                
                Button(windowController.isWindowVisible ? "Hide Window" : "Show Window") {
                    windowController.toggleWindow()
                }
                
                Divider()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

// Expose capture/apply for window buttons or other callers
extension AppDelegate {
    @objc func captureLayout() {
        DispatchQueue.global(qos: .userInitiated).async {
            let res = self.captureWithDisplayplacer()
            NSLog("displayplacer capture -> code=%d", res.code)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .displayScriptDidRun, object: nil, userInfo: [
                    "mode": "capture",
                    "code": res.code,
                    "output": res.output + (res.applyCmd != nil ? "\n\nSaved apply command:\n\(res.applyCmd!)" : "\n\nNo apply command found in output")
                ])
            }
        }
    }
    @objc func applyLayout() {
        DispatchQueue.global(qos: .userInitiated).async {
            let res = self.applySavedLayout()
            NSLog("displayplacer apply -> code=%d", res.code)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .displayScriptDidRun, object: nil, userInfo: [
                    "mode": "apply",
                    "code": res.code,
                    "output": res.output
                ])
            }
        }
    }
    // For Dry Run consumers
    @objc func buildDryRunApplyCommand() -> String? {
        guard let inner = buildInnerApplyShellLine() else { return nil }
        return "/bin/zsh -f -c \"\(inner.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

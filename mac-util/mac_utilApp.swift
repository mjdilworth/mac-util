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
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        // Show window immediately on app launch
        DispatchQueue.main.async {
            WindowController.shared.createAndShowWindow()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Don't quit when windows are closed
    }
}

@main
struct DillyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowController = WindowController.shared
    
    var body: some Scene {
        // Menu bar item
        MenuBarExtra("ServiceCtl", systemImage: "gearshape") {
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

import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine

// Class to monitor display changes
class DisplayMonitor: ObservableObject {
    @Published var displayMessage: String = ""
    private var previousScreens: [NSScreen] = NSScreen.screens
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit { NotificationCenter.default.removeObserver(self) }
    
    @objc private func screenParametersDidChange() {
        let current = NSScreen.screens
        var summary = "Display configuration changed (" + formattedDate() + ")"
        if current.count != previousScreens.count {
            summary += ": count \(previousScreens.count) -> \(current.count)"
        } else {
            summary += ": parameters updated"
        }
        previousScreens = current
        displayMessage = summary
    }
    
    private func formattedDate() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
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
    // Editor state
    @State private var isEditorPresented: Bool = false
    @State private var editorText: String = ""
    @State private var editorError: String? = nil

    private let defaults = UserDefaults.standard
    private let kAutoRun = "AutoRunEnabled"
    private let kDebounce = "DebounceSeconds"
    private let kSavedCmd = "DisplayplacerSavedCommand"

    init(showWindow: Binding<Bool>) {
        self._showWindow = showWindow
        let defaults = UserDefaults.standard
        let autoRun = defaults.object(forKey: kAutoRun) as? Bool ?? true
        let debounce = defaults.object(forKey: kDebounce) as? Double ?? 1.0
        self._autoRunEnabled = State(initialValue: autoRun)
        self._debounceSeconds = State(initialValue: debounce)
    }

    // MARK: - displayplacer helpers (local)
    private func displayplacerURL() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "displayplacer") { return url }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("displayplacer"), FileManager.default.isExecutableFile(atPath: res.path) { return res }
        let brewArm = URL(fileURLWithPath: "/opt/homebrew/bin/displayplacer")
        if FileManager.default.isExecutableFile(atPath: brewArm.path) { return brewArm }
        let brewIntel = URL(fileURLWithPath: "/usr/local/bin/displayplacer")
        if FileManager.default.isExecutableFile(atPath: brewIntel.path) { return brewIntel }
        return nil
    }
    
    private func captureWithDisplayplacer() -> (code: Int32, output: String, applyCmd: String?) {
        guard let dp = displayplacerURL() else { return (-1, "displayplacer not found in bundle or Homebrew paths", nil) }
        let task = Process(); let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = pipe
        task.executableURL = dp; task.arguments = ["list"]
        do { try task.run() } catch { return (-1, "Failed to run displayplacer: \(error.localizedDescription)", nil) }
        var didTimeout = false
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 10)
        timer.setEventHandler { if task.isRunning { didTimeout = true; task.terminate() } }
        timer.resume()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit(); timer.cancel()
        var out = String(data: data, encoding: .utf8) ?? ""
        if didTimeout { out += "\n\n[timeout] displayplacer list terminated after 10s." }
        let apply = parseApplyCommand(fromListOutput: out)
        if let apply { UserDefaults.standard.set(apply, forKey: kSavedCmd) }
        return (task.terminationStatus, out, apply)
    }
    
    private func parseApplyCommand(fromListOutput out: String) -> String? {
        guard let range = out.range(of: "displayplacer ", options: [.backwards]) else { return nil }
        var cmd = String(out[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let emptyRange = cmd.range(of: "\n\n") { cmd = String(cmd[..<emptyRange.lowerBound]) }
        return cmd
    }
    
    private func savedApplyCommand() -> String? {
        UserDefaults.standard.string(forKey: kSavedCmd)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Normalize and save/clear helpers for editor
    private func normalizeSavedCommand(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.range(of: "^\\s*displayplacer\\b", options: .regularExpression) != nil { return trimmed }
        return "displayplacer " + trimmed
    }
    
    private func setSavedApplyCommand(_ cmd: String?) {
        let trimmed = cmd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            defaults.removeObject(forKey: kSavedCmd)
        } else {
            defaults.set(trimmed, forKey: kSavedCmd)
        }
    }
    
    private func buildInnerApplyShellLine() -> String? {
        guard var saved = savedApplyCommand(), let dp = displayplacerURL() else { return nil }
        if let r = saved.range(of: "^\\s*displayplacer\\b", options: .regularExpression) {
            saved.replaceSubrange(r, with: "\"\(dp.path)\"")
        }
        return saved
    }
    
    private func applySavedLayout() -> (code: Int32, output: String) {
        guard let inner = buildInnerApplyShellLine() else { return (-1, "No saved layout or displayplacer not found") }
        let task = Process(); let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: "/bin/zsh"); task.arguments = ["-f", "-c", inner]
        do { try task.run() } catch { return (-1, "Failed to launch zsh: \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, out)
    }
    
    private func buildDryRunApplyCommand() -> String? {
        guard let inner = buildInnerApplyShellLine() else { return nil }
        return "/bin/zsh -f -c \"\(inner.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("Service Controller").font(.title)

            // Auto-Run toggle
            Button(action: {
                autoRunEnabled.toggle(); defaults.set(autoRunEnabled, forKey: kAutoRun)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: autoRunEnabled ? "play.circle.fill" : "pause.circle")
                    Text(autoRunEnabled ? "Auto-Run: ON" : "Auto-Run: OFF").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(autoRunEnabled ? .green : .gray)
            .help("Toggle automatic layout application on display change")

            // Manual controls
            HStack(spacing: 8) {
                let hasDP = (Bundle.main.url(forAuxiliaryExecutable: "displayplacer") != nil)
                    || ((Bundle.main.resourceURL?.appendingPathComponent("displayplacer").path).map { FileManager.default.isExecutableFile(atPath: $0) } ?? false)
                    || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/displayplacer")
                    || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/displayplacer")
                let hasSaved = (UserDefaults.standard.string(forKey: kSavedCmd)?.isEmpty == false)

                Button("Capture Now") {
                    let entry = "[\(formattedDate())] Starting capture…"
                    outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                    DispatchQueue.global(qos: .userInitiated).async {
                        let res = captureWithDisplayplacer()
                        DispatchQueue.main.async {
                            let direct = "[\(formattedDate())] Capture completed (code=\(res.code))\n\(res.output)\n\n" + (res.applyCmd != nil ? "Saved apply command:\n\(res.applyCmd!)" : "No apply command found in output")
                            outputText = outputText.isEmpty ? direct : "\(direct)\n\n\(outputText)"
                            NotificationCenter.default.post(name: .displayScriptDidRun, object: nil, userInfo: [
                                "mode": "capture", "code": res.code,
                                "output": res.output + (res.applyCmd != nil ? "\n\nSaved apply command:\n\(res.applyCmd!)" : "\n\nNo apply command found in output")
                            ])
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasDP)

                Button("Apply Layout") {
                    let entry = "[\(formattedDate())] Starting apply…"
                    outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                    DispatchQueue.global(qos: .userInitiated).async {
                        let res = applySavedLayout()
                        DispatchQueue.main.async {
                            let direct = "[\(formattedDate())] Apply completed (code=\(res.code))\n\(res.output)"
                            outputText = outputText.isEmpty ? direct : "\(direct)\n\n\(outputText)"
                            NotificationCenter.default.post(name: .displayScriptDidRun, object: nil, userInfo: [
                                "mode": "apply", "code": res.code, "output": res.output
                            ])
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!(hasDP && hasSaved))

                Button("Dry Run Apply") {
                    if let cmd = buildDryRunApplyCommand() {
                        let entry = "[\(formattedDate())] Dry run (apply) command\n\(cmd)"
                        outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                    } else {
                        let entry = "[\(formattedDate())] No saved layout or displayplacer not found"
                        outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!(hasDP && hasSaved))

                Button("Edit Saved Layout") {
                    editorText = savedApplyCommand() ?? "displayplacer "
                    editorError = nil
                    isEditorPresented = true
                }
                .buttonStyle(.bordered)

                Button("Clear Saved", role: .destructive) {
                    setSavedApplyCommand(nil)
                    let entry = "[\(formattedDate())] Cleared saved display layout"
                    outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                }
                .buttonStyle(.bordered)
                .disabled(!hasSaved)
                Spacer()
            }

            // Debounce
            HStack(spacing: 8) {
                Text("Debounce:").font(.callout).foregroundColor(.secondary)
                Stepper(value: $debounceSeconds, in: 0...10, step: 0.5) {
                    Text(String(format: "%.1f s", debounceSeconds)).font(.callout)
                }
                .onChange(of: debounceSeconds) { _, v in defaults.set(v, forKey: kDebounce) }
                Spacer()
            }

            // Log controls
            HStack {
                Spacer()
                Button("Clear Log") { outputText = "" }.buttonStyle(.bordered)
            }

            // Output text box with background and border (visual depth)
            ScrollView {
                Text(outputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 240, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))

            Button("Hide Window") { WindowController.shared.hideWindow() }
                .padding(.top, 8)
        }
        .frame(minWidth: 700, minHeight: 560)
        .padding(16)
        .onAppear {
            let screenDetails = getInitialScreenDetails()
            outputText = "[\(formattedDate())] Application started.\nCurrent displays:\n\(screenDetails)"
        }
        // Debounced screen-change auto-apply
        .onReceive(displayMonitor.$displayMessage
            .debounce(for: .seconds(debounceSeconds), scheduler: RunLoop.main)) { msg in
                guard !msg.isEmpty else { return }
                let note = "[\(formattedDate())] \(msg)"
                outputText = outputText.isEmpty ? note : "\(note)\n\n\(outputText)"
                guard autoRunEnabled, !isRunningScript else { return }
                isRunningScript = true
                DispatchQueue.global(qos: .utility).async {
                    let res = applySavedLayout()
                    DispatchQueue.main.async {
                        let entry = "[\(formattedDate())] Applied display layout (auto)\nExit code: \(res.code)\n\(res.output)"
                        outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                        isRunningScript = false
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .displayScriptDidRun)) { note in
            let mode = (note.userInfo?["mode"] as? String) ?? "?"
            let code = (note.userInfo?["code"] as? Int32) ?? -999
            let output = (note.userInfo?["output"] as? String) ?? ""
            let entry = "[\(formattedDate())] \(mode.capitalized) completed (code=\(code))\n\(output)"
            outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let v = defaults.object(forKey: kAutoRun) as? Bool ?? true
            if v != autoRunEnabled { autoRunEnabled = v }
        }
        // Editor sheet for saved layout
        .sheet(isPresented: $isEditorPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit Saved Display Layout").font(.headline)
                Text("Enter the full displayplacer command. You can paste from 'Capture Now'.").font(.callout).foregroundColor(.secondary)
                TextEditor(text: $editorText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                if let err = editorError {
                    Text(err).foregroundColor(.red).font(.footnote)
                }
                HStack {
                    Button("Cancel") { isEditorPresented = false }
                    Spacer()
                    Button("Clear", role: .destructive) {
                        setSavedApplyCommand(nil)
                        editorText = ""
                        let entry = "[\(formattedDate())] Cleared saved display layout"
                        outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                        isEditorPresented = false
                    }
                    Button("Save") {
                        let normalized = normalizeSavedCommand(editorText)
                        if normalized.isEmpty {
                            editorError = "Command cannot be empty."
                            return
                        }
                        setSavedApplyCommand(normalized)
                        let entry = "[\(formattedDate())] Saved display layout updated"
                        outputText = outputText.isEmpty ? entry : "\(entry)\n\n\(outputText)"
                        isEditorPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(minWidth: 640, minHeight: 340)
        }
    }

    // MARK: - Helpers
    private func formattedDate() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"; return formatter.string(from: Date())
    }
    
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
}

#Preview { ContentView(showWindow: .constant(true)) }

import Foundation
import Combine

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [AgentdTask] = []
    @Published var logs: [String: String] = [:]

    private let tasksDir: URL
    private let logsDir: URL
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.tasksDir = home.appendingPathComponent(".agentd/tasks")
        self.logsDir = home.appendingPathComponent(".agentd/logs")
        loadTasks()
        startWatching()
    }

    deinit {
        source?.cancel()
        timer?.invalidate()
    }

    func loadTasks() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: tasksDir.path) else {
            tasks = []
            return
        }

        do {
            let files = try fm.contentsOfDirectory(at: tasksDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }

            let decoder = JSONDecoder()
            var loaded: [AgentdTask] = []
            for file in files {
                do {
                    let data = try Data(contentsOf: file)
                    let task = try decoder.decode(AgentdTask.self, from: data)
                    loaded.append(task)
                } catch {
                    print("Warning: skipping corrupt task file \(file.lastPathComponent): \(error)")
                }
            }
            tasks = loaded.sorted { ($0.createdAtDate ?? .distantPast) > ($1.createdAtDate ?? .distantPast) }
        } catch {
            print("Failed to read tasks directory: \(error)")
            tasks = []
        }
    }

    func loadLog(for taskId: String) -> String? {
        let logFile = logsDir.appendingPathComponent("\(taskId).log")
        return try? String(contentsOf: logFile, encoding: .utf8)
    }

    func refreshLog(for taskId: String) {
        logs[taskId] = loadLog(for: taskId)
    }

    /// Updates the prompt in the task JSON file so the next agentd run uses the new prompt.
    /// Returns nil on success, or an error message string on failure.
    func updatePrompt(taskId: String, newPrompt: String) -> String? {
        let taskFile = tasksDir.appendingPathComponent("\(taskId).json")
        do {
            let data = try Data(contentsOf: taskFile)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Failed to parse task JSON"
            }
            json["prompt"] = newPrompt
            let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: taskFile)
            loadTasks()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Runs `agentd rm <id>` to properly unload plist and delete task + log files.
    /// Returns nil on success, or an error message string on failure.
    func removeTask(_ taskId: String) async -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "agentd rm \(taskId)"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                logs.removeValue(forKey: taskId)
                loadTasks()
                return nil
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return error.localizedDescription
        }
    }

    private func startWatching() {
        let fm = FileManager.default

        // Ensure directory exists before watching
        if !fm.fileExists(atPath: tasksDir.path) {
            try? fm.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        }

        // FSEvents for immediate response to file additions/removals
        let fd = open(tasksDir.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend],
                queue: .main
            )

            source.setEventHandler { [weak self] in
                self?.loadTasks()
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            self.source = source
        }

        // Polling to catch in-place file content changes (e.g., status, runCount, lastRun updates)
        // FSEvents on a directory only fires when files are added/removed, not when contents change
        startPolling()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadTasks()
            }
        }
    }
}

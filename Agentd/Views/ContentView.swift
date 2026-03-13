import SwiftUI

extension Notification.Name {
    static let saveEdit = Notification.Name("agentd.saveEdit")
    static let cancelEdit = Notification.Name("agentd.cancelEdit")
}

struct ContentView: View {
    @EnvironmentObject var store: TaskStore
    @State private var selectedTaskId: String?
    @State private var filter: TaskFilter = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingDeleteConfirm = false
    @State private var showingCheatsheet = false
    @State private var isEditingPrompt = false
    @State private var deleteError: String?
    @State private var showingDeleteError = false
    @State private var eventMonitor: Any?

    enum TaskFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        case failed = "Failed"

        var next: TaskFilter {
            let cases = TaskFilter.allCases
            let idx = cases.firstIndex(of: self)!
            return cases[(idx + 1) % cases.count]
        }

        var previous: TaskFilter {
            let cases = TaskFilter.allCases
            let idx = cases.firstIndex(of: self)!
            return cases[(idx - 1 + cases.count) % cases.count]
        }
    }

    var filteredTasks: [AgentdTask] {
        switch filter {
        case .all: store.tasks
        case .active: store.tasks.filter { $0.status == "active" }
        case .completed: store.tasks.filter { $0.status == "completed" }
        case .failed: store.tasks.filter { $0.status == "failed" }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                // Filter bar
                Picker("Filter", selection: $filter) {
                    ForEach(TaskFilter.allCases, id: \.self) { f in
                        Text(f.rawValue)
                            .tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)

                // Stats bar
                HStack(spacing: 16) {
                    StatBadge(label: "Active", count: store.tasks.filter { $0.status == "active" }.count, color: .statusActive)
                    StatBadge(label: "Done", count: store.tasks.filter { $0.status == "completed" }.count, color: .statusCompleted)
                    StatBadge(label: "Failed", count: store.tasks.filter { $0.status == "failed" }.count, color: .statusFailed)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider()

                if filteredTasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Tasks")
                            .font(.headline)
                        Text("Scheduled agent tasks from agentd will appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                    Spacer()
                } else {
                    List(filteredTasks, selection: $selectedTaskId) { task in
                        TaskRow(task: task)
                            .tag(task.id)
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                // Keyboard hints
                KeyHint(keys: ["?"], label: "keybindings")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            .toolbar {
                ToolbarItem {
                    Button {
                        store.loadTasks()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh tasks")
                }
            }
        } detail: {
            if let taskId = selectedTaskId,
               let task = store.tasks.first(where: { $0.id == taskId }) {
                TaskDetailView(
                    task: task,
                    selectedTaskId: $selectedTaskId,
                    isEditingPrompt: $isEditingPrompt,
                    showingDeleteConfirm: $showingDeleteConfirm
                )
            } else {
                ContentUnavailableView {
                    Label("Select a Task", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a scheduled task from the sidebar to view its details.")
                }
            }
        }
        .navigationTitle("Agentd")
        .overlay {
            if showingDeleteConfirm {
                deleteConfirmOverlay
            }
        }
        .overlay {
            if showingCheatsheet {
                cheatsheetOverlay
            }
        }
        .alert("Delete Failed", isPresented: $showingDeleteError) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "Unknown error")
        }
        .onAppear { setupKeyboardMonitor() }
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let key = event.charactersIgnoringModifiers ?? ""
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cheatsheet is showing - any key dismisses it
        if showingCheatsheet {
            showingCheatsheet = false
            return nil
        }

        // Delete confirmation is showing - only y/n/escape
        if showingDeleteConfirm {
            if key == "y" {
                performDelete()
                showingDeleteConfirm = false
                return nil
            } else if key == "n" || event.keyCode == 53 {
                showingDeleteConfirm = false
                return nil
            }
            return nil
        }

        // Editing mode - only handle escape and cmd+enter
        if isEditingPrompt {
            if event.keyCode == 53 {
                NotificationCenter.default.post(name: .cancelEdit, object: nil)
                return nil
            }
            if event.keyCode == 36 && modifiers.contains(.command) {
                NotificationCenter.default.post(name: .saveEdit, object: nil)
                return nil
            }
            return event
        }

        // Don't handle if command/control/option modifiers are pressed
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            return event
        }

        switch key {
        case "j":
            moveSelection(direction: .down)
            return nil
        case "k":
            moveSelection(direction: .up)
            return nil
        case "l":
            filter = filter.next
            return nil
        case "h":
            filter = filter.previous
            return nil
        case "a":
            filter = .all
            return nil
        case "d":
            if selectedTaskId != nil {
                showingDeleteConfirm = true
            }
            return nil
        case "r":
            store.loadTasks()
            return nil
        case "s":
            withAnimation {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
            return nil
        case "e":
            if selectedTaskId != nil && !isEditingPrompt {
                isEditingPrompt = true
            }
            return nil
        case "?":
            showingCheatsheet = true
            return nil
        default:
            return event
        }
    }

    private func moveSelection(direction: MoveDirection) {
        let tasks = filteredTasks
        guard !tasks.isEmpty else { return }

        guard let currentId = selectedTaskId,
              let currentIndex = tasks.firstIndex(where: { $0.id == currentId }) else {
            selectedTaskId = direction == .down ? tasks.first?.id : tasks.last?.id
            return
        }

        let newIndex: Int
        switch direction {
        case .down:
            newIndex = min(currentIndex + 1, tasks.count - 1)
        case .up:
            newIndex = max(currentIndex - 1, 0)
        }
        selectedTaskId = tasks[newIndex].id
    }

    private func performDelete() {
        guard let taskId = selectedTaskId else { return }
        Task {
            if let error = await store.removeTask(taskId) {
                deleteError = error
                showingDeleteError = true
            } else {
                selectedTaskId = nil
            }
        }
    }

    private enum MoveDirection {
        case up, down
    }

    // MARK: - Delete Confirmation Overlay

    private var deleteConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { showingDeleteConfirm = false }

            VStack(spacing: 16) {
                Image(systemName: "trash")
                    .font(.title)
                    .foregroundStyle(.red)

                Text("Delete Task?")
                    .font(.headline)

                Text("This will unload the launchd plist, delete the task, and remove its log. This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                HStack(spacing: 12) {
                    Button {
                        showingDeleteConfirm = false
                    } label: {
                        HStack(spacing: 4) {
                            Text("Cancel")
                            KeyHintInline(key: "n")
                        }
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        performDelete()
                        showingDeleteConfirm = false
                    } label: {
                        HStack(spacing: 4) {
                            Text("Delete")
                            KeyHintInline(key: "y")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }

    // MARK: - Cheatsheet Overlay

    private var cheatsheetOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { showingCheatsheet = false }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Keyboard Shortcuts")
                        .font(.headline)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    CheatsheetRow(keys: "j / k", description: "Move up / down")
                    CheatsheetRow(keys: "h / l", description: "Previous / next tab")
                    CheatsheetRow(keys: "a", description: "Show all tasks")
                    CheatsheetRow(keys: "d", description: "Delete task")
                    CheatsheetRow(keys: "e", description: "Edit prompt")
                    CheatsheetRow(keys: "r", description: "Refresh")
                    CheatsheetRow(keys: "s", description: "Toggle sidebar")
                    Divider()
                    CheatsheetRow(keys: "esc", description: "Cancel edit")
                    CheatsheetRow(keys: "\u{2318}\u{21A9}", description: "Save edit")
                    CheatsheetRow(keys: "y / n", description: "Confirm / cancel delete")
                    CheatsheetRow(keys: "?", description: "This cheatsheet")
                }

                Text("Press any key to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .frame(width: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }
}

// MARK: - Key Hint Views

struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 3))
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct KeyHintInline: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.secondary)
    }
}

struct CheatsheetRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.callout, design: .monospaced, weight: .medium))
                .frame(width: 80, alignment: .trailing)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatBadge: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.system(.caption, design: .monospaced, weight: .medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

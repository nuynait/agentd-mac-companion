import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TaskStore
    @State private var selectedTaskId: String?
    @State private var filter: TaskFilter = .all

    enum TaskFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        case failed = "Failed"
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
        NavigationSplitView {
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
                TaskDetailView(task: task, selectedTaskId: $selectedTaskId)
            } else {
                ContentUnavailableView {
                    Label("Select a Task", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a scheduled task from the sidebar to view its details.")
                }
            }
        }
        .navigationTitle("Agentd")
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

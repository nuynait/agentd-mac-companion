import SwiftUI

struct TaskDetailView: View {
    let task: AgentdTask
    @Binding var selectedTaskId: String?
    @Binding var isEditingPrompt: Bool
    @Binding var showingDeleteConfirm: Bool
    @EnvironmentObject var store: TaskStore
    @State private var editedPrompt: String = ""
    @State private var promptSaveError: String?
    @State private var showingPromptSaveError = false
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        scrollContent
            .navigationTitle(task.id)
            .toolbar { toolbarContent }
            .onChange(of: isEditingPrompt) { _, editing in
                if editing {
                    editedPrompt = task.prompt
                    isPromptFocused = true
                } else {
                    isPromptFocused = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cancelEdit)) { _ in
                isEditingPrompt = false
                editedPrompt = task.prompt
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveEdit)) { _ in
                savePrompt()
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                infoGrid
                workingDirectorySection
                promptSection
                if let context = task.context {
                    contextSection(context)
                }
                stopConditionsSection
                logSection
            }
            .padding(24)
        }
    }

    private var infoGrid: some View {
        let scheduleIcon = task.schedule.isRecurring ? "repeat" : "clock"
        let createdValue = DateFormatting.localString(from: task.createdAt)
        return LazyVGrid(columns: [
            GridItem(.flexible(), alignment: .topLeading),
            GridItem(.flexible(), alignment: .topLeading),
        ], spacing: 16) {
            InfoCard(title: "Provider", value: task.provider.capitalized, icon: task.provider == "claude" ? "brain" : "terminal")
            InfoCard(title: "Status", value: task.status.capitalized, icon: "circle.fill", color: statusColor)
            InfoCard(title: "Schedule", value: task.schedule.description, icon: scheduleIcon)
            InfoCard(title: "Run Count", value: "\(task.runCount)", icon: "number")
            InfoCard(title: "Created", value: createdValue, icon: "calendar")
            if let lastRun = task.lastRunDate {
                InfoCard(title: "Last Run", value: DateFormatting.localString(from: lastRun), icon: "clock.arrow.circlepath")
            }
        }
    }

    private var workingDirectorySection: some View {
        DetailSection(title: "Working Directory") {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(task.cwd)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var promptSection: some View {
        DetailSection(title: "Prompt") {
            VStack(alignment: .leading, spacing: 8) {
                if isEditingPrompt {
                    TextEditor(text: $editedPrompt)
                        .focused($isPromptFocused)
                        .font(.body)
                        .frame(minHeight: 80)
                        .padding(4)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1))
                    HStack(spacing: 8) {
                        Button("Cancel") {
                            isEditingPrompt = false
                            editedPrompt = task.prompt
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        KeyHintInline(key: "esc")

                        Spacer()

                        Button("Save") {
                            savePrompt()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedPrompt == task.prompt)

                        KeyHintInline(key: "\u{2318}\u{21A9}")
                    }
                } else {
                    Text(task.prompt)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 6) {
                        Button("Edit Prompt") {
                            editedPrompt = task.prompt
                            isEditingPrompt = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        KeyHintInline(key: "e")
                    }
                }
            }
            .alert("Save Failed", isPresented: $showingPromptSaveError) {
                Button("OK") {}
            } message: {
                Text(promptSaveError ?? "Unknown error")
            }
        }
    }

    private func savePrompt() {
        let trimmed = editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, editedPrompt != task.prompt else { return }
        if let error = store.updatePrompt(taskId: task.id, newPrompt: editedPrompt) {
            promptSaveError = error
            showingPromptSaveError = true
        } else {
            isEditingPrompt = false
        }
    }

    @ViewBuilder
    private var stopConditionsSection: some View {
        if let stops = task.stopConditions, !stops.isEmpty {
            DetailSection(title: "Stop Conditions") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                        Label(stop.description, systemImage: "stop.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if let conditional = task.conditionalStop {
            DetailSection(title: "Conditional Stop") {
                Label(conditional.condition, systemImage: "questionmark.circle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var logSection: some View {
        DetailSection(title: "Log Output") {
            LogView(taskId: task.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                store.refreshLog(for: task.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh log")
        }
        ToolbarItem {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.statusFailed)
            }
            .help("Delete task")
        }
    }

    private var statusColor: Color {
        .forStatus(task.status)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusDot(status: task.status)
                    Text(task.id)
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                }
                Text(task.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            StatusPill(status: task.status)
        }
    }

    @ViewBuilder
    private func contextSection(_ context: TaskContext) -> some View {
        DetailSection(title: "Git Context") {
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .topLeading),
                GridItem(.flexible(), alignment: .topLeading),
            ], spacing: 8) {
                if let branch = context.gitBranch {
                    ContextItem(label: "Branch", value: branch, icon: "arrow.triangle.branch")
                }
                if let repo = context.gitRepo {
                    ContextItem(label: "Repo", value: repo, icon: "shippingbox")
                }
                if let commit = context.gitCommit {
                    ContextItem(label: "Commit", value: commit, icon: "number")
                }
                if let defaultBranch = context.gitDefaultBranch {
                    ContextItem(label: "Default Branch", value: defaultBranch, icon: "arrow.triangle.branch")
                }
                if let prNumber = context.prNumber {
                    ContextItem(label: "PR", value: "#\(prNumber)", icon: "arrow.triangle.pull", link: context.prUrl)
                }
                if let issueNumber = context.issueNumber {
                    ContextItem(label: "Issue", value: "#\(issueNumber)", icon: "exclamationmark.circle")
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatusPill: View {
    let status: String

    var color: Color {
        .forStatus(status)
    }

    var body: some View {
        Text(status.uppercased())
            .font(.system(.caption, design: .monospaced, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color != .primary ? color : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(color != .primary ? color : .primary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, weight: .semibold))
            content
        }
    }
}

struct ContextItem: View {
    let label: String
    let value: String
    let icon: String
    var link: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let link, let url = URL(string: link) {
                    Link(value, destination: url)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

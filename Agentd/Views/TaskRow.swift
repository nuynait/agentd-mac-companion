import SwiftUI

struct TaskRow: View {
    let task: AgentdTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusDot(status: task.status)
                Text(task.prompt)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label(task.provider, systemImage: task.provider == "claude" ? "brain" : "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(task.schedule.raw, systemImage: task.schedule.isRecurring ? "repeat" : "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if task.runCount > 0 {
                    Text("\(task.runCount) run\(task.runCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let lastRun = task.lastRunDate {
                    Text(lastRun, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let repo = task.context?.gitRepo {
                    Text(repo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shared Status Colors

extension Color {
    static let statusActive = Color(red: 0.30, green: 0.75, blue: 0.55)
    static let statusCompleted = Color(red: 0.45, green: 0.60, blue: 0.85)
    static let statusFailed = Color(red: 0.90, green: 0.45, blue: 0.45)

    static func forStatus(_ status: String) -> Color {
        switch status {
        case "active": .statusActive
        case "completed": .statusCompleted
        case "failed": .statusFailed
        default: .secondary
        }
    }
}

struct StatusDot: View {
    let status: String

    var body: some View {
        Circle()
            .fill(Color.forStatus(status))
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .fill(Color.forStatus(status).opacity(0.25))
                    .frame(width: 16, height: 16)
            )
    }
}

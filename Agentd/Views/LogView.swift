import SwiftUI

struct LogView: View {
    let taskId: String
    @EnvironmentObject var store: TaskStore
    @AppStorage("logFontSize") var logFontSize: Double = 11
    @State private var logContent: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let content = logContent ?? store.logs[taskId] {
                if content.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical) {
                        Text(content)
                            .font(.system(size: logFontSize, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 400)
                    .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                }
            } else {
                emptyState
            }

            HStack {
                Button("Load Log") {
                    store.refreshLog(for: taskId)
                    logContent = store.logs[taskId]
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if logContent != nil || store.logs[taskId] != nil {
                    Button("Refresh") {
                        store.refreshLog(for: taskId)
                        logContent = store.logs[taskId]
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            store.refreshLog(for: taskId)
            logContent = store.logs[taskId]
        }
        .onChange(of: taskId) { _, newId in
            store.refreshLog(for: newId)
            logContent = store.logs[newId]
        }
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.tertiary)
            Text("No log output yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    @State private var showTokenEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.hasToken {
                content
            } else {
                tokenSetup
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Octobar")
                    .font(.title3.bold())

                Spacer()

                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Actionable items: \(model.actionableCount)")
                .font(.subheadline)

            if let login = model.userLogin {
                Text("Signed in as @\(login)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastUpdated = model.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Assigned Pull Requests", count: model.assignedPullRequests.count)
                if model.assignedPullRequests.isEmpty {
                    Text("No open pull requests assigned to you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.assignedPullRequests.prefix(8)) { pullRequest in
                        Link(destination: pullRequest.url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pullRequest.title)
                                    .font(.callout)
                                    .lineLimit(2)
                                Text("#\(pullRequest.number) · \(pullRequest.repository)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }

                sectionHeader("Action Required Runs", count: model.actionRequiredRuns.count)
                if model.actionRequiredRuns.isEmpty {
                    Text("No workflow runs with status action_required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.actionRequiredRuns.prefix(8)) { run in
                        Link(destination: run.url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.title)
                                    .font(.callout)
                                    .lineLimit(2)
                                Text("\(run.repository) · \(run.status) · \(run.event)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }

                sectionHeader("Post-Merge Workflow Watch", count: model.postMergeWatchItems.count)
                if model.postMergeWatchItems.isEmpty {
                    Text("No recently merged PRs tracked yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.postMergeWatchItems.prefix(8)) { item in
                        Link(destination: item.destinationURL) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.callout)
                                    .lineLimit(2)

                                HStack(spacing: 4) {
                                    Text("#\(item.number) · \(item.repository)")
                                    Text("·")
                                    Text(item.status.label)
                                        .foregroundStyle(statusColor(item.status))
                                }
                                .font(.caption)

                                if item.status == .failed, let failedRun = item.failedRuns.first {
                                    Text("Failed: \(failedRun.name) (\(failedRun.conclusion))")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                } else {
                                    Text("Runs on merge commit: \(item.totalRuns)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }

                sectionHeader("Actionable Notifications", count: model.actionableNotifications.count)
                if model.actionableNotifications.isEmpty {
                    Text("No actionable notifications right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.actionableNotifications.prefix(8)) { notification in
                        Link(destination: notification.url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notification.title)
                                    .font(.callout)
                                    .lineLimit(2)
                                Text("\(notification.repository) · \(notification.reason)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
    }

    private var tokenSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a GitHub personal access token to start polling your queue.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("ghp_...", text: $model.tokenInput)
                .textFieldStyle(.roundedBorder)

            Button("Save Token") {
                model.saveToken()
            }

            Text("Required scopes depend on your repos. Start with read access to repository metadata, pull requests, actions, and notifications.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Poll every 60 seconds",
                isOn: Binding(
                    get: { model.pollingEnabled },
                    set: { model.setPollingEnabled($0) }
                )
            )
            .disabled(!model.hasToken)

            HStack {
                Button("Refresh Now") {
                    model.refreshNow()
                }
                .disabled(!model.hasToken)

                Button(showTokenEditor ? "Hide Token" : "Edit Token") {
                    showTokenEditor.toggle()
                }
                .disabled(!model.hasToken)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }

            if model.hasToken, showTokenEditor {
                SecureField("Update token", text: $model.tokenInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save") {
                        model.saveToken()
                    }

                    Button("Clear") {
                        model.clearToken()
                    }

                    Spacer()
                }
            }

            HStack {
                Link("GitHub Notifications", destination: URL(string: "https://github.com/notifications")!)
                Link("Assigned PRs", destination: URL(string: "https://github.com/pulls/assigned")!)
            }
            .font(.caption)
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func statusColor(_ status: PostMergeWorkflowStatus) -> Color {
        switch status {
        case .failed:
            return .red
        case .pending:
            return .orange
        case .succeeded:
            return .green
        case .noRuns:
            return .secondary
        }
    }
}

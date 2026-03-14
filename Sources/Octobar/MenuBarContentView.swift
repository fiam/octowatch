import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openURL) private var openURL

    @State private var showTokenEditor = false
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.hasToken {
                queueHeader
                attentionList
            } else {
                tokenSetup
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 420)
    }

    private var queueHeader: some View {
        HStack(spacing: 8) {
            Text("\(model.actionableCount)")
                .font(.title3.bold())
                .monospacedDigit()

            Text(model.actionableCount == 1 ? "item needs attention" : "items need attention")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if model.unreadCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.blue)
                    Text("\(model.unreadCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var attentionList: some View {
        Group {
            if model.attentionItems.isEmpty {
                Text("Nothing requiring attention right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.attentionItems.prefix(30)) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.type.iconName)
                                    .frame(width: 16)
                                    .foregroundStyle(iconColor(for: item.type))

                                Button {
                                    model.toggleReadState(for: item)
                                } label: {
                                    Image(systemName: item.isUnread ? "circle.fill" : "circle")
                                        .font(.system(size: 8))
                                        .frame(width: 12)
                                        .foregroundStyle(item.isUnread ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help(item.isUnread ? "Mark as read" : "Mark as unread")

                                Button {
                                    model.markItemAsRead(item)
                                    openURL(item.url)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(item.isUnread ? .callout.weight(.semibold) : .callout)
                                            .lineLimit(2)

                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Text(relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private var tokenSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a GitHub personal access token to start polling your attention queue.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("ghp_...", text: $model.tokenInput)
                .textFieldStyle(.roundedBorder)

            Button("Save Token") {
                model.saveToken()
            }

            Text("If gh is authenticated, Octobar can import token automatically via `gh auth token`.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(
                    "Poll every 60s",
                    isOn: Binding(
                        get: { model.pollingEnabled },
                        set: { model.setPollingEnabled($0) }
                    )
                )
                .disabled(!model.hasToken)

                Spacer()

                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(model.relativeLastUpdated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Refresh") {
                    model.refreshNow()
                }
                .disabled(!model.hasToken)

                Button(showTokenEditor ? "Hide Token" : "Edit Token") {
                    showTokenEditor.toggle()
                }
                .disabled(!model.hasToken)

                Spacer()

                Link("Notifications", destination: URL(string: "https://github.com/notifications")!)
                    .font(.caption)

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
        }
    }

    private func iconColor(for itemType: AttentionItemType) -> Color {
        switch itemType {
        case .assignedPullRequest:
            return .blue
        case .actionableNotification:
            return .secondary
        case .actionRequiredRun:
            return .orange
        }
    }
}

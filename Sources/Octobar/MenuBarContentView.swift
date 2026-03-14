import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.hasToken {
                attentionList
            } else {
                tokenSetup
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 420)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            openSettings()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if model.hasToken {
                    Text("\(model.actionableCount)")
                        .font(.title3.bold())
                        .monospacedDigit()

                    Text(model.actionableCount == 1 ? "item needs attention" : "items need attention")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

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
                } else {
                    Text("GitHub token required")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }

                settingsButton
            }

            if model.hasToken {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(model.relativeLastUpdated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Open Settings to add your GitHub token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var settingsButton: some View {
        SettingsLink {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help("Settings")
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
        VStack(alignment: .leading, spacing: 6) {
            Text("No attention queue yet.")
                .font(.callout.weight(.semibold))
            Text("Add a token in Settings. Octobar can auto-import one via `gh auth token`.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsLink {
                Text("Open Settings")
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

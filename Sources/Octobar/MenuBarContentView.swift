import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
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
        .onReceive(NotificationCenter.default.publisher(for: .performMainWindowOpen)) { _ in
            openWindow(id: AppSceneID.mainWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSettingsOpen)) { _ in
            openSettings()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            windowButton
        }
    }

    private var windowButton: some View {
        Button(action: requestMainWindow) {
            Image(systemName: "macwindow")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help("Open Octowatch")
    }

    private var attentionList: some View {
        Group {
            if model.attentionItems.isEmpty {
                Text("Inbox is clear right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.attentionItems.prefix(30)) { item in
                            HStack(alignment: .top, spacing: 10) {
                                eventBadge(for: item.type)

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

                                VStack(alignment: .trailing, spacing: 6) {
                                    if let actor = item.actor {
                                        ActorAvatarView(actor: actor)
                                    }

                                    Text(relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date()))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                }
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
            Text("GitHub isn't connected yet.")
                .font(.callout.weight(.semibold))
            Text("Open Settings to validate GitHub CLI or provide a personal access token.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: requestSettings) {
                Text("Open Settings")
            }
        }
    }

    private func requestSettings() {
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }

    private func requestMainWindow() {
        NotificationCenter.default.post(name: .openMainWindowRequested, object: nil)
    }

    @ViewBuilder
    private func eventBadge(for itemType: AttentionItemType) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(iconBackground(for: itemType))
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: itemType.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor(for: itemType))
            }
            .accessibilityLabel(itemType.accessibilityLabel)
    }

    private func iconColor(for itemType: AttentionItemType) -> Color {
        switch itemType {
        case .assignedPullRequest:
            return .blue
        case .comment, .reviewComment:
            return .secondary
        case .mention:
            return .purple
        case .reviewRequested:
            return .indigo
        case .reviewApproved:
            return .green
        case .reviewChangesRequested:
            return .orange
        case .pullRequestStateChanged:
            return .brown
        case .ciActivity:
            return .teal
        case .workflowFailed:
            return .red
        case .workflowApprovalRequired:
            return .orange
        }
    }

    private func iconBackground(for itemType: AttentionItemType) -> Color {
        switch itemType {
        case .assignedPullRequest:
            return .blue.opacity(0.14)
        case .comment, .reviewComment:
            return .secondary
                .opacity(0.12)
        case .mention:
            return .purple.opacity(0.14)
        case .reviewRequested:
            return .indigo.opacity(0.14)
        case .reviewApproved:
            return .green.opacity(0.14)
        case .reviewChangesRequested:
            return .orange.opacity(0.14)
        case .pullRequestStateChanged:
            return .brown.opacity(0.14)
        case .ciActivity:
            return .teal.opacity(0.14)
        case .workflowFailed:
            return .red.opacity(0.14)
        case .workflowApprovalRequired:
            return .orange.opacity(0.14)
        }
    }
}

private struct ActorAvatarView: View {
    let actor: AttentionActor

    var body: some View {
        Group {
            if let avatarURL = actor.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .help(actor.login)
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
    }
}

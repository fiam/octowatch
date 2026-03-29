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
                yourTurnList
            } else {
                tokenSetup
            }

            footer
        }
        .padding(12)
        .frame(width: 360)
        .onReceive(NotificationCenter.default.publisher(for: .performMainWindowOpen)) { _ in
            openWindow(id: AppSceneID.mainWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSettingsOpen)) { _ in
            openSettings()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            let count = model.yourTurnItems.count
            Text("Your Turn")
                .font(.headline)
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: requestMainWindow) {
                Image(systemName: "macwindow")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .appInteractiveHover(backgroundOpacity: 0.08, cornerRadius: 8)
            .help("Open Octowatch")
        }
    }

    private var yourTurnList: some View {
        Group {
            if model.yourTurnItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text("Nothing waiting on you")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.yourTurnItems.prefix(20)) { item in
                            Button {
                                openURL(item.url)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    eventBadge(for: item)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                        Text(itemContext(for: item))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .appInteractiveHover(backgroundOpacity: 0.06, cornerRadius: 10)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if model.lastUpdated != nil {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text("Updated \(relativeFormatter.localizedString(for: model.lastUpdated ?? .now, relativeTo: context.date))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(action: requestSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .appInteractiveHover(backgroundOpacity: 0.08, cornerRadius: 6)
            .help("Settings")
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
            .appInteractiveHover()
        }
    }

    private func itemContext(for item: AttentionItem) -> String {
        let typeSummary = item.type.nativeNotificationTitle
        if let repo = item.repository {
            return "\(repo) · \(typeSummary)"
        }
        return typeSummary
    }

    private func requestSettings() {
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }

    private func requestMainWindow() {
        NotificationCenter.default.post(name: .openMainWindowRequested, object: nil)
    }

    @ViewBuilder
    private func eventBadge(for item: AttentionItem) -> some View {
        let helpText = AttentionItemType.badgeHelpText(
            primary: item.type,
            secondary: item.secondaryIndicatorType
        )

        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(iconBackground(for: item.type))
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor(for: item.type))
            }
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private func iconColor(for itemType: AttentionItemType) -> Color {
        switch itemType {
        case .assignedPullRequest:
            return .blue
        case .authoredPullRequest:
            return .teal
        case .reviewedPullRequest:
            return .indigo
        case .commentedPullRequest:
            return .cyan
        case .readyToMerge:
            return .green
        case .pullRequestMergeConflicts:
            return .orange
        case .pullRequestFailedChecks:
            return .red
        case .assignedIssue:
            return .orange
        case .authoredIssue:
            return .brown
        case .commentedIssue:
            return .secondary
        case .comment, .reviewComment:
            return .secondary
        case .mention:
            return .purple
        case .teamMention:
            return .pink
        case .newCommitsAfterComment:
            return .teal
        case .newCommitsAfterReview:
            return .cyan
        case .reviewRequested:
            return .indigo
        case .teamReviewRequested:
            return .mint
        case .reviewApproved:
            return .green
        case .reviewChangesRequested:
            return .orange
        case .pullRequestStateChanged:
            return .brown
        case .ciActivity:
            return .teal
        case .workflowRunning:
            return .blue
        case .workflowSucceeded:
            return .green
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
        case .authoredPullRequest:
            return .teal.opacity(0.14)
        case .reviewedPullRequest:
            return .indigo.opacity(0.14)
        case .commentedPullRequest:
            return .cyan.opacity(0.16)
        case .readyToMerge:
            return .green.opacity(0.16)
        case .pullRequestMergeConflicts:
            return .orange.opacity(0.16)
        case .pullRequestFailedChecks:
            return .red.opacity(0.14)
        case .assignedIssue:
            return .orange.opacity(0.16)
        case .authoredIssue:
            return .brown.opacity(0.16)
        case .commentedIssue:
            return .secondary.opacity(0.12)
        case .comment, .reviewComment:
            return .secondary.opacity(0.12)
        case .mention:
            return .purple.opacity(0.14)
        case .teamMention:
            return .pink.opacity(0.14)
        case .newCommitsAfterComment:
            return .teal.opacity(0.14)
        case .newCommitsAfterReview:
            return .cyan.opacity(0.16)
        case .reviewRequested:
            return .indigo.opacity(0.14)
        case .teamReviewRequested:
            return .mint.opacity(0.18)
        case .reviewApproved:
            return .green.opacity(0.14)
        case .reviewChangesRequested:
            return .orange.opacity(0.14)
        case .pullRequestStateChanged:
            return .brown.opacity(0.14)
        case .ciActivity:
            return .teal.opacity(0.14)
        case .workflowRunning:
            return .blue.opacity(0.14)
        case .workflowSucceeded:
            return .green.opacity(0.14)
        case .workflowFailed:
            return .red.opacity(0.14)
        case .workflowApprovalRequired:
            return .orange.opacity(0.14)
        }
    }
}

struct BotAccountChip: View {
    let login: String
    var compact: Bool = false

    var body: some View {
        Image(systemName: "cpu")
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 3 : 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )
            .help("\(login) is a bot account")
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

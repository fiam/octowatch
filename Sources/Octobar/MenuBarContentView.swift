import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @State private var workflowApprovalSheetRequest: WorkflowApprovalSheetRequest?

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
        .sheet(item: $workflowApprovalSheetRequest) { request in
            WorkflowPendingDeploymentReviewSheet(
                model: model,
                request: request,
                onOpenGitHub: { url in
                    openURL(url)
                }
            )
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
        .appInteractiveHover(backgroundOpacity: 0.08, cornerRadius: 8)
        .help("Open Octowatch")
    }

    private var attentionList: some View {
        Group {
            if model.actionableAttentionItems.isEmpty {
                Text("Inbox is clear right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.actionableAttentionItems.prefix(30)) { item in
                            HStack(alignment: .top, spacing: 10) {
                                eventBadge(for: item)

                                Button {
                                    model.toggleReadState(for: item)
                                } label: {
                                    Image(systemName: item.isUnread ? "circle.fill" : "circle")
                                        .font(.system(size: 8))
                                        .frame(width: 12)
                                        .foregroundStyle(item.isUnread ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                .appInteractiveHover(backgroundOpacity: 0.06, cornerRadius: 8)
                                .help(item.isUnread ? "Mark as read" : "Mark as unread")

                                Button {
                                    model.markItemAsRead(item)
                                    openURL(item.url)
                                } label: {
                                    let contextSubtitle = AttentionViewerPresentationPolicy.listContextSubtitle(
                                        subtitle: item.subtitle,
                                        actor: item.actor,
                                        repository: item.repository,
                                        viewerLogin: model.viewerLogin,
                                        hidesRepository: false
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(item.isUnread ? .callout.weight(.semibold) : .callout)
                                            .lineLimit(2)

                                        if let contextSubtitle {
                                            Text(contextSubtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        HStack(alignment: .center, spacing: 6) {
                                            if let actor = item.actor {
                                                let actorPresentation =
                                                    AttentionViewerPresentationPolicy.actorPresentation(
                                                        for: actor,
                                                        viewerLogin: model.viewerLogin
                                                    )

                                                HStack(alignment: .center, spacing: 6) {
                                                    ActorAvatarView(actor: actor)

                                                    Text(actorPresentation.label)
                                                        .font(.caption.weight(.medium))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)

                                                    if actorPresentation.showsBotBadge {
                                                        BotAccountChip(
                                                            login: actor.login,
                                                            compact: true
                                                        )
                                                    }
                                                }
                                            }

                                            Spacer(minLength: 8)

                                            RelativeTimestampText(
                                                date: item.timestamp,
                                                formatter: relativeFormatter
                                            )
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .appInteractiveHover(backgroundOpacity: 0.06, cornerRadius: 10)

                                if let workflowApprovalRequest = WorkflowApprovalSheetRequest(item: item) {
                                    Button {
                                        model.markItemAsRead(item)
                                        workflowApprovalSheetRequest = workflowApprovalRequest
                                    } label: {
                                        Image(systemName: "hand.raised")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(6)
                                    }
                                    .buttonStyle(.plain)
                                    .appInteractiveHover(backgroundOpacity: 0.06, cornerRadius: 8)
                                    .help("Review pending deployments")
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
            .appInteractiveHover()
        }
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
            .overlay(alignment: .bottomTrailing) {
                if let secondaryType = item.secondaryIndicatorType {
                    Circle()
                        .fill(Color(NSColor.windowBackgroundColor))
                        .frame(width: 12, height: 12)
                        .overlay {
                            Circle()
                                .fill(iconBackground(for: secondaryType))
                            Image(systemName: compactSecondaryIconName(for: secondaryType))
                                .font(.system(size: 5, weight: .bold))
                                .foregroundStyle(iconColor(for: secondaryType))
                        }
                        .offset(x: 3, y: 3)
                }
            }
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private func compactSecondaryIconName(for itemType: AttentionItemType) -> String {
        switch itemType {
        case .workflowApprovalRequired:
            return "hand.raised.fill"
        case .workflowRunning:
            return "clock.fill"
        case .workflowSucceeded:
            return "checkmark"
        case .workflowFailed:
            return "xmark"
        default:
            return itemType.iconName
        }
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
            return .secondary
                .opacity(0.12)
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

private struct RelativeTimestampText: View {
    let date: Date
    let formatter: RelativeDateTimeFormatter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(formatter.localizedString(for: date, relativeTo: context.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
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

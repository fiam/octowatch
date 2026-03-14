import Foundation

enum AttentionItemType: String, Hashable, Sendable {
    case assignedPullRequest
    case comment
    case mention
    case reviewRequested
    case reviewApproved
    case reviewChangesRequested
    case reviewComment
    case pullRequestStateChanged
    case ciActivity
    case workflowFailed
    case workflowApprovalRequired

    var iconName: String {
        switch self {
        case .assignedPullRequest:
            return "arrow.triangle.pull"
        case .comment:
            return "text.bubble"
        case .mention:
            return "at"
        case .reviewRequested:
            return "person.badge.key"
        case .reviewApproved:
            return "checkmark.bubble"
        case .reviewChangesRequested:
            return "exclamationmark.bubble"
        case .reviewComment:
            return "bubble.left.and.text.bubble.right"
        case .pullRequestStateChanged:
            return "arrow.trianglehead.branch"
        case .ciActivity:
            return "bolt.badge.clock"
        case .workflowFailed:
            return "bolt.trianglebadge.exclamationmark"
        case .workflowApprovalRequired:
            return "hand.raised.square.on.square"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .assignedPullRequest:
            return "Assigned pull request"
        case .comment:
            return "New comment"
        case .mention:
            return "Mention"
        case .reviewRequested:
            return "Review requested"
        case .reviewApproved:
            return "Review approved"
        case .reviewChangesRequested:
            return "Changes requested"
        case .reviewComment:
            return "Review comment"
        case .pullRequestStateChanged:
            return "Pull request state changed"
        case .ciActivity:
            return "Continuous integration activity"
        case .workflowFailed:
            return "Workflow failed"
        case .workflowApprovalRequired:
            return "Workflow waiting for approval"
        }
    }

    var nativeNotificationTitle: String {
        switch self {
        case .assignedPullRequest:
            return "Pull request assigned"
        case .comment:
            return "New comment"
        case .mention:
            return "New mention"
        case .reviewRequested:
            return "Review requested"
        case .reviewApproved:
            return "Review approved"
        case .reviewChangesRequested:
            return "Changes requested"
        case .reviewComment:
            return "New review comment"
        case .pullRequestStateChanged:
            return "Pull request updated"
        case .ciActivity:
            return "CI activity"
        case .workflowFailed:
            return "Workflow failed"
        case .workflowApprovalRequired:
            return "Workflow waiting for approval"
        }
    }

    var actorVerb: String {
        switch self {
        case .assignedPullRequest:
            return "assigned a pull request"
        case .comment:
            return "commented"
        case .mention:
            return "mentioned you"
        case .reviewRequested:
            return "requested your review"
        case .reviewApproved:
            return "approved a pull request"
        case .reviewChangesRequested:
            return "requested changes"
        case .reviewComment:
            return "left a review comment"
        case .pullRequestStateChanged:
            return "updated pull request state"
        case .ciActivity:
            return "triggered CI activity"
        case .workflowFailed:
            return "triggered a failing workflow"
        case .workflowApprovalRequired:
            return "triggered a workflow awaiting approval"
        }
    }

    static func notificationType(
        reason: String,
        timelineEvent: String?,
        reviewState: String?
    ) -> AttentionItemType {
        let normalizedEvent = timelineEvent?.lowercased()
        let normalizedState = reviewState?.lowercased()

        switch normalizedEvent {
        case "review_requested":
            return .reviewRequested
        case "reviewed":
            switch normalizedState {
            case "approved":
                return .reviewApproved
            case "changes_requested":
                return .reviewChangesRequested
            default:
                return .reviewComment
            }
        case "commented":
            return .comment
        case "closed", "merged", "reopened", "head_ref_force_pushed", "committed":
            return .pullRequestStateChanged
        case "assigned":
            return .assignedPullRequest
        default:
            break
        }

        switch reason.lowercased() {
        case "assign":
            return .assignedPullRequest
        case "mention", "team_mention":
            return .mention
        case "review_requested":
            return .reviewRequested
        case "author", "comment", "subscribed", "manual":
            return .comment
        case "state_change":
            return .pullRequestStateChanged
        case "ci_activity":
            return .ciActivity
        default:
            return .comment
        }
    }

    static func workflowType(status: String?, conclusion: String?) -> AttentionItemType? {
        let normalizedStatus = (status ?? "").lowercased()
        let normalizedConclusion = (conclusion ?? "").lowercased()

        if normalizedStatus == "action_required" || normalizedConclusion == "action_required" {
            return .workflowApprovalRequired
        }

        let failingConclusions: Set<String> = [
            "failure",
            "timed_out",
            "startup_failure"
        ]
        if failingConclusions.contains(normalizedConclusion) {
            return .workflowFailed
        }

        return nil
    }
}

struct AttentionActor: Hashable, Sendable {
    let login: String
    let avatarURL: URL?
}

struct AttentionItem: Identifiable, Hashable, Sendable {
    let id: String
    let type: AttentionItemType
    let title: String
    let subtitle: String
    let timestamp: Date
    let url: URL
    let actor: AttentionActor?
    var isUnread: Bool

    init(
        id: String,
        type: AttentionItemType,
        title: String,
        subtitle: String,
        timestamp: Date,
        url: URL,
        actor: AttentionActor? = nil,
        isUnread: Bool = true
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.url = url
        self.actor = actor
        self.isUnread = isUnread
    }

    var nativeNotificationTitle: String {
        guard let actor else {
            return type.nativeNotificationTitle
        }

        return "\(actor.login) \(type.actorVerb)"
    }
}

struct PullRequestSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let subtitle: String
    let repository: String
    let url: URL
    let updatedAt: Date
}

struct NotificationSummary: Identifiable, Hashable, Sendable {
    let id: String
    let type: AttentionItemType
    let title: String
    let subtitle: String
    let repository: String
    let url: URL
    let updatedAt: Date
    let unread: Bool
    let actor: AttentionActor?
}

struct ActionRunSummary: Identifiable, Hashable, Sendable {
    let id: String
    let type: AttentionItemType
    let title: String
    let subtitle: String
    let repository: String
    let createdAt: Date
    let url: URL
    let actor: AttentionActor?
}

struct GitHubSnapshot: Sendable {
    let login: String
    let attentionItems: [AttentionItem]
}

enum PullRequestAttentionPolicy {
    static func shouldIncludeActivity(
        state: String,
        merged: Bool,
        closedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        if state.lowercased() == "open" && !merged {
            return true
        }

        guard let closedAt else {
            return false
        }

        return closedAt >= now.addingTimeInterval(-86_400)
    }

    static func shouldWatchWorkflows(
        state: String,
        merged: Bool,
        mergedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        if state.lowercased() == "open" && !merged {
            return true
        }

        guard merged, let mergedAt else {
            return false
        }

        return mergedAt >= now.addingTimeInterval(-86_400)
    }
}

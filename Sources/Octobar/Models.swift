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
    let ignoreKey: String
    let type: AttentionItemType
    let title: String
    let subtitle: String
    let timestamp: Date
    let url: URL
    let actor: AttentionActor?
    var isUnread: Bool

    init(
        id: String,
        ignoreKey: String,
        type: AttentionItemType,
        title: String,
        subtitle: String,
        timestamp: Date,
        url: URL,
        actor: AttentionActor? = nil,
        isUnread: Bool = true
    ) {
        self.id = id
        self.ignoreKey = ignoreKey
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

    var ignoreActionTitle: String {
        if ignoreKey.contains("/pull/") {
            return "Ignore Pull Request"
        }

        if ignoreKey.contains("/issues/") {
            return "Ignore Issue"
        }

        return "Ignore Item"
    }
}

struct PullRequestSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let ignoreKey: String
    let number: Int
    let title: String
    let subtitle: String
    let repository: String
    let url: URL
    let updatedAt: Date
}

struct NotificationSummary: Identifiable, Hashable, Sendable {
    let id: String
    let ignoreKey: String
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
    let ignoreKey: String
    let type: AttentionItemType
    let title: String
    let subtitle: String
    let repository: String
    let createdAt: Date
    let url: URL
    let actor: AttentionActor?
}

enum AutoMarkReadSetting: Int, CaseIterable, Hashable, Sendable {
    case never = 0
    case oneSecond = 1
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never:
            return "Never"
        case .oneSecond:
            return "1 second"
        case .threeSeconds:
            return "3 seconds"
        case .fiveSeconds:
            return "5 seconds"
        case .tenSeconds:
            return "10 seconds"
        }
    }

    var delay: Duration? {
        switch self {
        case .never:
            return nil
        case .oneSecond:
            return .seconds(1)
        case .threeSeconds:
            return .seconds(3)
        case .fiveSeconds:
            return .seconds(5)
        case .tenSeconds:
            return .seconds(10)
        }
    }

    static func normalized(rawValue: Int) -> AutoMarkReadSetting {
        AutoMarkReadSetting(rawValue: rawValue) ?? .threeSeconds
    }
}

struct GitHubRateLimit: Hashable, Sendable {
    let limit: Int
    let remaining: Int
    let resetAt: Date?
    let pollIntervalHintSeconds: Int?
    let retryAfterSeconds: Int?

    var isExhausted: Bool {
        remaining <= 0
    }

    var isLow: Bool {
        remaining <= max(25, min(100, limit / 50))
    }

    func merged(with other: GitHubRateLimit) -> GitHubRateLimit {
        let preferred = isMoreRestrictive(than: other) ? self : other

        return GitHubRateLimit(
            limit: preferred.limit,
            remaining: preferred.remaining,
            resetAt: preferred.resetAt ?? other.resetAt,
            pollIntervalHintSeconds: mergedOptionalMax(
                pollIntervalHintSeconds,
                other.pollIntervalHintSeconds
            ),
            retryAfterSeconds: mergedOptionalMax(
                retryAfterSeconds,
                other.retryAfterSeconds
            )
        )
    }

    func minimumAutomaticRefreshInterval(
        userConfiguredSeconds: Int,
        now: Date = .now
    ) -> Int {
        var interval = max(userConfiguredSeconds, pollIntervalHintSeconds ?? 0)

        if let retryAfterSeconds {
            interval = max(interval, retryAfterSeconds)
        }

        if isExhausted, let resetAt {
            interval = max(interval, Int(ceil(resetAt.timeIntervalSince(now))))
        } else if remaining <= 25 {
            interval = max(interval, 900)
        } else if remaining <= 100 {
            interval = max(interval, 300)
        }

        return max(interval, userConfiguredSeconds)
    }

    private func isMoreRestrictive(than other: GitHubRateLimit) -> Bool {
        if isExhausted != other.isExhausted {
            return isExhausted
        }

        if remaining != other.remaining {
            return remaining < other.remaining
        }

        let lhsHint = max(pollIntervalHintSeconds ?? 0, retryAfterSeconds ?? 0)
        let rhsHint = max(other.pollIntervalHintSeconds ?? 0, other.retryAfterSeconds ?? 0)
        if lhsHint != rhsHint {
            return lhsHint > rhsHint
        }

        switch (resetAt, other.resetAt) {
        case let (.some(lhs), .some(rhs)):
            return lhs > rhs
        case (.some, .none):
            return true
        default:
            return false
        }
    }

    private func mergedOptionalMax(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return max(lhs, rhs)
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }
}

struct GitHubSnapshot: Sendable {
    let login: String
    let attentionItems: [AttentionItem]
    let rateLimit: GitHubRateLimit?
}

struct IgnoredAttentionSubject: Identifiable, Hashable, Codable, Sendable {
    let ignoreKey: String
    let title: String
    let subtitle: String
    let url: URL
    let ignoredAt: Date

    var id: String { ignoreKey }

    static func placeholder(for ignoreKey: String, ignoredAt: Date = .now) -> IgnoredAttentionSubject {
        if let url = URL(string: ignoreKey),
            let parsed = placeholder(fromCanonicalURL: url, ignoredAt: ignoredAt) {
            return parsed
        }

        if ignoreKey.hasPrefix("issue:") {
            let value = String(ignoreKey.dropFirst(6))
            let components = value.split(separator: "#", maxSplits: 1).map(String.init)
            if components.count == 2 {
                let url = URL(string: "https://github.com/\(components[0])/issues/\(components[1])")!
                return IgnoredAttentionSubject(
                    ignoreKey: url.absoluteString,
                    title: "Issue #\(components[1])",
                    subtitle: components[0],
                    url: url,
                    ignoredAt: ignoredAt
                )
            }
        }

        if ignoreKey.hasPrefix("pr:") {
            let value = String(ignoreKey.dropFirst(3))
            let components = value.split(separator: "#", maxSplits: 1).map(String.init)
            if components.count == 2 {
                let url = URL(string: "https://github.com/\(components[0])/pull/\(components[1])")!
                return IgnoredAttentionSubject(
                    ignoreKey: url.absoluteString,
                    title: "Pull Request #\(components[1])",
                    subtitle: components[0],
                    url: url,
                    ignoredAt: ignoredAt
                )
            }
        }

        if ignoreKey.hasPrefix("url:"),
            let url = URL(string: String(ignoreKey.dropFirst(4))),
            let parsed = placeholder(fromCanonicalURL: url, ignoredAt: ignoredAt) {
            return parsed
        }

        if let url = URL(string: ignoreKey) {
            return IgnoredAttentionSubject(
                ignoreKey: url.absoluteString,
                title: "Ignored Item",
                subtitle: url.host ?? "GitHub",
                url: url,
                ignoredAt: ignoredAt
            )
        }

        return IgnoredAttentionSubject(
            ignoreKey: ignoreKey,
            title: "Ignored Item",
            subtitle: "GitHub",
            url: URL(string: "https://github.com")!,
            ignoredAt: ignoredAt
        )
    }

    private static func placeholder(
        fromCanonicalURL url: URL,
        ignoredAt: Date
    ) -> IgnoredAttentionSubject? {
        let components = url.pathComponents

        if let pullIndex = components.firstIndex(of: "pull"),
            pullIndex >= 2,
            pullIndex + 1 < components.count {
            let repository = "\(components[pullIndex - 2])/\(components[pullIndex - 1])"
            let number = components[pullIndex + 1]
            return IgnoredAttentionSubject(
                ignoreKey: url.absoluteString,
                title: "Pull Request #\(number)",
                subtitle: repository,
                url: url,
                ignoredAt: ignoredAt
            )
        }

        if let issueIndex = components.firstIndex(of: "issues"),
            issueIndex >= 2,
            issueIndex + 1 < components.count {
            let repository = "\(components[issueIndex - 2])/\(components[issueIndex - 1])"
            let number = components[issueIndex + 1]
            return IgnoredAttentionSubject(
                ignoreKey: url.absoluteString,
                title: "Issue #\(number)",
                subtitle: repository,
                url: url,
                ignoredAt: ignoredAt
            )
        }

        return nil
    }
}

enum AttentionItemVisibilityPolicy {
    static func excludingIgnoredSubjects(
        _ items: [AttentionItem],
        ignoredKeys: Set<String>
    ) -> [AttentionItem] {
        items.filter { !ignoredKeys.contains($0.ignoreKey) }
    }
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

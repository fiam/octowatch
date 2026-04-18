import Foundation

enum AttentionStream: String, CaseIterable, Hashable, Sendable {
    case notifications
    case pullRequests
    case issues

    var title: String {
        switch self {
        case .notifications:
            return "Notifications"
        case .pullRequests:
            return "Pull Requests"
        case .issues:
            return "Issues"
        }
    }

    var iconName: String {
        switch self {
        case .notifications:
            return "bell.badge"
        case .pullRequests:
            return "arrow.triangle.pull"
        case .issues:
            return "exclamationmark.circle"
        }
    }
}

enum PullRequestDashboardFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case created
    case assigned
    case mentioned
    case reviewRequests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .created:
            return "Created"
        case .assigned:
            return "Assigned"
        case .mentioned:
            return "Mentioned"
        case .reviewRequests:
            return "Review Requests"
        }
    }
}

enum IssueDashboardFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case created
    case assigned
    case mentioned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .created:
            return "Created"
        case .assigned:
            return "Assigned"
        case .mentioned:
            return "Mentioned"
        }
    }
}

struct PullRequestDashboard: Hashable, Sendable {
    let created: [AttentionItem]
    let assigned: [AttentionItem]
    let mentioned: [AttentionItem]
    let reviewRequests: [AttentionItem]

    static let empty = PullRequestDashboard(
        created: [],
        assigned: [],
        mentioned: [],
        reviewRequests: []
    )

    subscript(filter: PullRequestDashboardFilter) -> [AttentionItem] {
        switch filter {
        case .created:
            return created
        case .assigned:
            return assigned
        case .mentioned:
            return mentioned
        case .reviewRequests:
            return reviewRequests
        }
    }

    func filteringIgnoredSubjects(_ ignoredKeys: Set<String>) -> PullRequestDashboard {
        PullRequestDashboard(
            created: created.filter { !ignoredKeys.contains($0.ignoreKey) },
            assigned: assigned.filter { !ignoredKeys.contains($0.ignoreKey) },
            mentioned: mentioned.filter { !ignoredKeys.contains($0.ignoreKey) },
            reviewRequests: reviewRequests.filter { !ignoredKeys.contains($0.ignoreKey) }
        )
    }

    func filteringSnoozedSubjects(_ snoozedKeys: Set<String>) -> PullRequestDashboard {
        PullRequestDashboard(
            created: created.filter { !snoozedKeys.contains($0.ignoreKey) },
            assigned: assigned.filter { !snoozedKeys.contains($0.ignoreKey) },
            mentioned: mentioned.filter { !snoozedKeys.contains($0.ignoreKey) },
            reviewRequests: reviewRequests.filter { !snoozedKeys.contains($0.ignoreKey) }
        )
    }
}

struct IssueDashboard: Hashable, Sendable {
    let created: [AttentionItem]
    let assigned: [AttentionItem]
    let mentioned: [AttentionItem]

    static let empty = IssueDashboard(
        created: [],
        assigned: [],
        mentioned: []
    )

    subscript(filter: IssueDashboardFilter) -> [AttentionItem] {
        switch filter {
        case .created:
            return created
        case .assigned:
            return assigned
        case .mentioned:
            return mentioned
        }
    }

    func filteringIgnoredSubjects(_ ignoredKeys: Set<String>) -> IssueDashboard {
        IssueDashboard(
            created: created.filter { !ignoredKeys.contains($0.ignoreKey) },
            assigned: assigned.filter { !ignoredKeys.contains($0.ignoreKey) },
            mentioned: mentioned.filter { !ignoredKeys.contains($0.ignoreKey) }
        )
    }

    func filteringSnoozedSubjects(_ snoozedKeys: Set<String>) -> IssueDashboard {
        IssueDashboard(
            created: created.filter { !snoozedKeys.contains($0.ignoreKey) },
            assigned: assigned.filter { !snoozedKeys.contains($0.ignoreKey) },
            mentioned: mentioned.filter { !snoozedKeys.contains($0.ignoreKey) }
        )
    }
}

enum AttentionCombinedViewPolicy {
    static func collapsingDuplicates(in items: [AttentionItem]) -> [AttentionItem] {
        AttentionSubjectViewPolicy.collapsingUpdates(in: items)
    }
}

enum AttentionSection: String, CaseIterable, Hashable, Sendable {
    case pullRequests
    case issues
    case workflows
    case notifications

    var title: String {
        switch self {
        case .pullRequests:
            return "Pull Requests"
        case .issues:
            return "Issues"
        case .workflows:
            return "Workflows"
        case .notifications:
            return "Notifications"
        }
    }

    var iconName: String {
        switch self {
        case .pullRequests:
            return AttentionStream.pullRequests.iconName
        case .issues:
            return AttentionStream.issues.iconName
        case .workflows:
            return "bolt.horizontal.circle"
        case .notifications:
            return AttentionStream.notifications.iconName
        }
    }

    var itemNoun: String {
        switch self {
        case .pullRequests:
            return "pull request item"
        case .issues:
            return "issue item"
        case .workflows:
            return "workflow item"
        case .notifications:
            return "notification"
        }
    }

    var emptyTitle: String {
        switch self {
        case .pullRequests:
            return "No pull request items"
        case .issues:
            return "No issue items"
        case .workflows:
            return "No workflows"
        case .notifications:
            return "No notifications"
        }
    }

    var emptyUnreadTitle: String {
        switch self {
        case .pullRequests:
            return "No unread pull request items"
        case .issues:
            return "No unread issue items"
        case .workflows:
            return "No unread workflows"
        case .notifications:
            return "No unread notifications"
        }
    }

    var focusedSectionTitle: String {
        switch self {
        case .pullRequests:
            return "Pull Request Activity"
        case .issues:
            return "Issue Activity"
        case .workflows:
            return "Workflow Activity"
        case .notifications:
            return "GitHub Notifications"
        }
    }
}

enum AttentionSectionPolicy {
    static func section(for item: AttentionItem) -> AttentionSection {
        if item.type.isWorkflowActivityType {
            return .workflows
        }

        if isGitHubNotificationPrimary(item) {
            return .notifications
        }

        if item.pullRequestReference != nil ||
            item.subjectReference?.kind == .pullRequest ||
            item.stream == .pullRequests {
            return .pullRequests
        }

        if item.subjectReference?.kind == .issue || item.stream == .issues {
            return .issues
        }

        return .notifications
    }

    static func isGitHubNotificationPrimary(_ item: AttentionItem) -> Bool {
        item.updateKey.hasPrefix("notif:") || item.latestSourceID.hasPrefix("notif:")
    }
}

enum AttentionItemType: String, Hashable, Codable, Sendable {
    case assignedPullRequest
    case authoredPullRequest
    case reviewedPullRequest
    case commentedPullRequest
    case readyToMerge
    case pullRequestMergeConflicts
    case pullRequestFailedChecks
    case assignedIssue
    case authoredIssue
    case commentedIssue
    case securityAlert
    case comment
    case mention
    case teamMention
    case newCommitsAfterComment
    case newCommitsAfterReview
    case reviewRequested
    case teamReviewRequested
    case reviewApproved
    case reviewChangesRequested
    case reviewComment
    case pullRequestStateChanged
    case ciActivity
    case workflowRunning
    case workflowSucceeded
    case workflowFailed
    case workflowApprovalRequired

    var iconName: String {
        switch self {
        case .assignedPullRequest:
            return "arrow.triangle.pull"
        case .authoredPullRequest:
            return "arrow.triangle.pull"
        case .reviewedPullRequest:
            return "arrow.triangle.pull"
        case .commentedPullRequest:
            return "arrow.triangle.pull"
        case .readyToMerge:
            return "checkmark.circle"
        case .pullRequestMergeConflicts:
            return "arrow.triangle.branch"
        case .pullRequestFailedChecks:
            return "xmark.octagon"
        case .assignedIssue:
            return "exclamationmark.circle"
        case .authoredIssue:
            return "exclamationmark.circle"
        case .commentedIssue:
            return "exclamationmark.circle"
        case .securityAlert:
            return "exclamationmark.shield"
        case .comment:
            return "text.bubble"
        case .mention:
            return "at"
        case .teamMention:
            return "person.3.fill"
        case .newCommitsAfterComment, .newCommitsAfterReview:
            return "arrow.trianglehead.branch"
        case .reviewRequested:
            return "person.badge.key"
        case .teamReviewRequested:
            return "person.2.fill"
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
        case .workflowRunning:
            return "bolt.badge.clock"
        case .workflowSucceeded:
            return "checkmark.circle"
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
        case .authoredPullRequest:
            return "Your pull request"
        case .reviewedPullRequest:
            return "Reviewed pull request"
        case .commentedPullRequest:
            return "Commented pull request"
        case .readyToMerge:
            return "Ready to merge"
        case .pullRequestMergeConflicts:
            return "Merge conflicts"
        case .pullRequestFailedChecks:
            return "Failed checks"
        case .assignedIssue:
            return "Assigned issue"
        case .authoredIssue:
            return "Your issue"
        case .commentedIssue:
            return "Commented issue"
        case .securityAlert:
            return "Security alert"
        case .comment:
            return "New comment"
        case .mention:
            return "Mentioned you"
        case .teamMention:
            return "Team mention"
        case .newCommitsAfterComment:
            return "New commits after your comment"
        case .newCommitsAfterReview:
            return "New commits after your review"
        case .reviewRequested:
            return "Review requested"
        case .teamReviewRequested:
            return "Team review requested"
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
        case .workflowRunning:
            return "Workflow running"
        case .workflowSucceeded:
            return "Workflow succeeded"
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
        case .authoredPullRequest:
            return "Your pull request"
        case .reviewedPullRequest:
            return "Reviewed pull request"
        case .commentedPullRequest:
            return "Commented pull request"
        case .readyToMerge:
            return "Ready to merge"
        case .pullRequestMergeConflicts:
            return "Merge conflicts"
        case .pullRequestFailedChecks:
            return "Failed checks"
        case .assignedIssue:
            return "Issue assigned"
        case .authoredIssue:
            return "Your issue"
        case .commentedIssue:
            return "Commented issue"
        case .securityAlert:
            return "Security alert"
        case .comment:
            return "New comment"
        case .mention:
            return "New mention"
        case .teamMention:
            return "New team mention"
        case .newCommitsAfterComment:
            return "New commits after comment"
        case .newCommitsAfterReview:
            return "New commits after review"
        case .reviewRequested:
            return "Review requested"
        case .teamReviewRequested:
            return "Team review requested"
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
        case .workflowRunning:
            return "Workflow running"
        case .workflowSucceeded:
            return "Workflow succeeded"
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
        case .authoredPullRequest:
            return "updated your pull request"
        case .reviewedPullRequest:
            return "updated a pull request you reviewed"
        case .commentedPullRequest:
            return "updated a pull request you commented on"
        case .readyToMerge:
            return "approved your pull request"
        case .pullRequestMergeConflicts:
            return "updated your pull request with merge conflicts"
        case .pullRequestFailedChecks:
            return "updated your pull request with failed checks"
        case .assignedIssue:
            return "assigned an issue"
        case .authoredIssue:
            return "updated your issue"
        case .commentedIssue:
            return "updated an issue you commented on"
        case .securityAlert:
            return "raised a security alert"
        case .comment:
            return "commented"
        case .mention:
            return "mentioned you"
        case .teamMention:
            return "mentioned one of your teams"
        case .newCommitsAfterComment:
            return "pushed new commits after your comment"
        case .newCommitsAfterReview:
            return "pushed new commits after your review"
        case .reviewRequested:
            return "requested your review"
        case .teamReviewRequested:
            return "requested a team review"
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
        case .workflowRunning:
            return "started a workflow"
        case .workflowSucceeded:
            return "finished a workflow successfully"
        case .workflowFailed:
            return "triggered a failing workflow"
        case .workflowApprovalRequired:
            return "triggered a workflow awaiting approval"
        }
    }

    static func notificationType(
        reason: String,
        timelineEvent: String?,
        reviewState: String?,
        teamScoped: Bool = false,
        followUpRelationship: NotificationFollowUpRelationship? = nil
    ) -> AttentionItemType {
        let normalizedReason = reason.lowercased()
        let normalizedEvent = timelineEvent?.lowercased()
        let normalizedState = reviewState?.lowercased()

        if normalizedReason == "security_alert" {
            return .securityAlert
        }

        if normalizedReason == "review_requested", followUpRelationship == nil {
            return teamScoped ? .teamReviewRequested : .reviewRequested
        }

        switch normalizedEvent {
        case "review_requested":
            return teamScoped ? .teamReviewRequested : .reviewRequested
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
        case "head_ref_force_pushed", "committed":
            switch followUpRelationship {
            case .afterYourComment:
                return .newCommitsAfterComment
            case .afterYourReview:
                return .newCommitsAfterReview
            case nil:
                return .pullRequestStateChanged
            }
        case "closed", "merged", "reopened":
            return .pullRequestStateChanged
        case "assigned":
            return .assignedPullRequest
        default:
            break
        }

        switch normalizedReason {
        case "assign":
            return .assignedPullRequest
        case "mention":
            return .mention
        case "team_mention":
            return .teamMention
        case "review_requested":
            return teamScoped ? .teamReviewRequested : .reviewRequested
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

    static func workflowType(
        status: String?,
        conclusion: String?,
        requiresApproval: Bool = false
    ) -> AttentionItemType? {
        let normalizedStatus = (status ?? "").lowercased()
        let normalizedConclusion = (conclusion ?? "").lowercased()

        if requiresApproval {
            return .workflowApprovalRequired
        }

        let runningStatuses: Set<String> = [
            "queued",
            "in_progress",
            "pending",
            "requested",
            "waiting"
        ]

        if runningStatuses.contains(normalizedStatus) && normalizedConclusion.isEmpty {
            return .workflowRunning
        }

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

        if normalizedStatus == "completed" && normalizedConclusion == "success" {
            return .workflowSucceeded
        }

        return nil
    }

    var isWorkflowActivity: Bool {
        switch self {
        case .workflowRunning, .workflowSucceeded, .workflowFailed, .workflowApprovalRequired:
            return true
        default:
            return false
        }
    }

    var defaultStream: AttentionStream {
        switch self {
        case .assignedPullRequest,
                .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .readyToMerge,
                .pullRequestMergeConflicts,
                .pullRequestFailedChecks,
                .ciActivity,
                .workflowRunning,
                .workflowSucceeded,
                .workflowFailed,
                .workflowApprovalRequired:
            return .pullRequests
        case .assignedIssue,
                .authoredIssue,
                .commentedIssue:
            return .issues
        case .comment,
                .securityAlert,
                .mention,
                .teamMention,
                .newCommitsAfterComment,
                .newCommitsAfterReview,
                .reviewRequested,
                .teamReviewRequested,
                .reviewApproved,
                .reviewChangesRequested,
                .reviewComment,
                .pullRequestStateChanged:
            return .notifications
        }
    }
}

struct AttentionActor: Hashable, Codable, Sendable {
    let login: String
    let avatarURL: URL?
    private let profileURLOverride: URL?
    private let isBotOverride: Bool?

    init(login: String, avatarURL: URL?, profileURL: URL? = nil, isBot: Bool? = nil) {
        self.login = login
        self.avatarURL = avatarURL
        self.profileURLOverride = profileURL
        self.isBotOverride = isBot
    }

    var isBotAccount: Bool {
        if let isBotOverride {
            return isBotOverride
        }

        let normalized = login.lowercased()
        return normalized.hasSuffix("[bot]") || normalized.hasPrefix("app/")
    }

    var profileURL: URL {
        profileURLOverride ?? URL(string: "https://github.com/\(login)")!
    }

    var displayLogin: String {
        let botSuffix = "[bot]"
        guard login.lowercased().hasSuffix(botSuffix) else {
            return login
        }

        let trimmed = String(login.dropLast(botSuffix.count))
        return trimmed.isEmpty ? login : trimmed
    }

    func isSameAccount(as other: AttentionActor) -> Bool {
        login.caseInsensitiveCompare(other.login) == .orderedSame
    }
}

enum NotificationFollowUpRelationship: Hashable, Sendable {
    case afterYourComment
    case afterYourReview
}

struct AttentionWhy: Hashable, Sendable {
    let summary: String
    let detail: String?
}

struct GitHubLabel: Identifiable, Hashable, Sendable {
    let name: String
    let colorHex: String
    let description: String?

    var id: String {
        "\(name.lowercased())#\(colorHex.lowercased())"
    }
}

struct AttentionEvidence: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String?
    let iconName: String
    let url: URL?

    init(
        id: String,
        title: String,
        detail: String? = nil,
        iconName: String,
        url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.iconName = iconName
        self.url = url
    }
}

struct AttentionAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let iconName: String
    let url: URL
    let isPrimary: Bool

    init(
        id: String,
        title: String,
        iconName: String,
        url: URL,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.url = url
        self.isPrimary = isPrimary
    }
}

struct AttentionUpdate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let type: AttentionItemType
    let title: String
    let detail: String?
    let timestamp: Date
    let actor: AttentionActor?
    let url: URL?
    let isTriggeredByCurrentUser: Bool

    init(
        id: String,
        type: AttentionItemType,
        title: String,
        detail: String?,
        timestamp: Date,
        actor: AttentionActor?,
        url: URL?,
        isTriggeredByCurrentUser: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.actor = actor
        self.url = url
        self.isTriggeredByCurrentUser = isTriggeredByCurrentUser
    }

    var workflowApprovalTarget: WorkflowApprovalTarget? {
        guard type == .workflowApprovalRequired, let url else {
            return nil
        }

        return WorkflowApprovalTarget(url: url)
    }
}

struct AttentionDetail: Hashable, Sendable {
    let contextPillTitle: String?
    let why: AttentionWhy
    let evidence: [AttentionEvidence]
    let updates: [AttentionUpdate]
    let actions: [AttentionAction]
    let acknowledgement: String?

    init(
        contextPillTitle: String? = nil,
        why: AttentionWhy,
        evidence: [AttentionEvidence],
        updates: [AttentionUpdate] = [],
        actions: [AttentionAction],
        acknowledgement: String? = nil
    ) {
        self.contextPillTitle = contextPillTitle
        self.why = why
        self.evidence = evidence
        self.updates = updates
        self.actions = actions
        self.acknowledgement = acknowledgement
    }
}

enum AttentionUpdateHistoryPolicy {
    static func merging(
        existing: [AttentionUpdate],
        current: [AttentionUpdate],
        limit: Int? = nil
    ) -> [AttentionUpdate] {
        let sorted = (current + existing).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id > rhs.id
            }
            return lhs.timestamp > rhs.timestamp
        }

        var merged = [AttentionUpdate]()
        var seen = Set<String>()
        for update in sorted {
            guard seen.insert(update.id).inserted else {
                continue
            }
            merged.append(update)
            if let limit, merged.count == limit {
                break
            }
        }

        return merged
    }

    static func pruningInvalidWorkflowUpdates(
        _ updates: [AttentionUpdate],
        mergedAt: Date?
    ) -> [AttentionUpdate] {
        updates.filter {
            WorkflowRunAttributionPolicy.shouldRetainHistoricalUpdate($0, mergedAt: mergedAt)
        }
    }
}

enum AttentionUpdateHistoryProjection {
    static func applying(
        persistedHistoryBySubjectKey: [String: [AttentionUpdate]],
        to items: [AttentionItem]
    ) -> (items: [AttentionItem], historyBySubjectKey: [String: [AttentionUpdate]]) {
        var historyBySubjectKey = persistedHistoryBySubjectKey.filter { !$0.value.isEmpty }

        let itemsWithHistory = items.map { item in
            let mergedUpdates = AttentionUpdateHistoryPolicy.merging(
                existing: historyBySubjectKey[item.subjectKey] ?? [],
                current: item.detail.updates
            )

            if mergedUpdates.isEmpty {
                historyBySubjectKey[item.subjectKey] = nil
            } else {
                historyBySubjectKey[item.subjectKey] = mergedUpdates
            }

            let detail = AttentionDetail(
                contextPillTitle: item.detail.contextPillTitle,
                why: item.detail.why,
                evidence: item.detail.evidence,
                updates: mergedUpdates,
                actions: item.detail.actions,
                acknowledgement: item.detail.acknowledgement
            )

            return item.replacing(detail: detail)
        }

        return (itemsWithHistory, historyBySubjectKey)
    }
}

enum AttentionUpdateHistoryStore {
    static func load(from defaults: UserDefaults, key: String) -> [String: [AttentionUpdate]] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let history = try? decoder.decode([String: [AttentionUpdate]].self, from: data) else {
            return [:]
        }

        return history.filter { !$0.value.isEmpty }
    }

    static func persist(
        _ historyBySubjectKey: [String: [AttentionUpdate]],
        to defaults: UserDefaults,
        key: String
    ) {
        let filteredHistory = historyBySubjectKey.filter { !$0.value.isEmpty }
        guard !filteredHistory.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(filteredHistory) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

struct AttentionSubjectRefresh: Sendable {
    static let localSupplementalItemIDPrefix = "focus-supplemental:"

    let subjectKey: String
    let labels: [GitHubLabel]
    let mergedAt: Date?
    let supplementalItems: [AttentionItem]
}

enum AttentionSubjectRefreshPolicy {
    static func applying(
        _ refresh: AttentionSubjectRefresh,
        to items: [AttentionItem]
    ) -> [AttentionItem] {
        let filteredItems = items.filter { item in
            !(item.subjectKey == refresh.subjectKey &&
                item.id.hasPrefix(AttentionSubjectRefresh.localSupplementalItemIDPrefix))
        }

        let relabeledItems = filteredItems.map { item in
            guard item.subjectKey == refresh.subjectKey else {
                return item
            }

            return item.replacing(labels: refresh.labels)
        }

        return relabeledItems + refresh.supplementalItems
    }
}

enum AttentionUpdateNotificationPolicy {
    static func shouldDeliver(
        item: AttentionItem,
        includeSelfTriggeredUpdates: Bool
    ) -> Bool {
        includeSelfTriggeredUpdates || !item.isTriggeredByCurrentUser
    }
}

struct PullRequestReference: Hashable, Codable, Sendable {
    let owner: String
    let name: String
    let number: Int

    var repository: String {
        "\(owner)/\(name)"
    }

    var pullRequestURL: URL {
        URL(string: "https://github.com/\(repository)/pull/\(number)")!
    }

    var filesURL: URL {
        pullRequestURL.appending(path: "files")
    }

    var commitsURL: URL {
        pullRequestURL.appending(path: "commits")
    }

    var checksURL: URL {
        pullRequestURL.appending(path: "checks")
    }
}

struct WorkflowApprovalTarget: Identifiable, Hashable, Codable, Sendable {
    let repository: String
    let runID: Int
    let url: URL

    var id: String {
        "\(repository)#\(runID)"
    }

    init(repository: String, runID: Int, url: URL) {
        self.repository = repository
        self.runID = runID
        self.url = url
    }

    init?(url: URL) {
        let components = url.pathComponents
        guard
            let actionsIndex = components.firstIndex(of: "actions"),
            actionsIndex >= 2,
            actionsIndex + 2 < components.count,
            components[actionsIndex + 1] == "runs",
            let runID = Int(components[actionsIndex + 2])
        else {
            return nil
        }

        self.init(
            repository: "\(components[actionsIndex - 2])/\(components[actionsIndex - 1])",
            runID: runID,
            url: url
        )
    }
}

enum GitHubSubjectKind: Hashable, Sendable {
    case pullRequest
    case issue
}

struct GitHubSubjectReference: Hashable, Sendable {
    let owner: String
    let name: String
    let number: Int
    let kind: GitHubSubjectKind

    var repository: String {
        "\(owner)/\(name)"
    }

    var webURL: URL {
        switch kind {
        case .pullRequest:
            return URL(string: "https://github.com/\(repository)/pull/\(number)")!
        case .issue:
            return URL(string: "https://github.com/\(repository)/issues/\(number)")!
        }
    }

    func labelSearchURL(for label: GitHubLabel) -> URL {
        var components = URLComponents(
            string: "https://github.com/\(repository)/\(kind.searchPathComponent)"
        )!
        let escapedLabel = label.name.replacingOccurrences(of: "\"", with: "\\\"")
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: "\(kind.searchQualifier) label:\"\(escapedLabel)\""
            )
        ]
        return components.url!
    }
}

private extension GitHubSubjectKind {
    var searchPathComponent: String {
        switch self {
        case .pullRequest:
            return "pulls"
        case .issue:
            return "issues"
        }
    }

    var searchQualifier: String {
        switch self {
        case .pullRequest:
            return "is:pr"
        case .issue:
            return "is:issue"
        }
    }
}

enum GitHubSubjectResolution: Hashable, Sendable {
    case open
    case closed
    case merged
}

struct PullRequestLiveWatchState: Hashable, Sendable {
    let reference: PullRequestReference
    let resolution: GitHubSubjectResolution
    let isInMergeQueue: Bool
    let headSHA: String?
    let latestTimelineMarker: String?
    let detailsETag: String?
    let timelineETag: String?
}

struct PullRequestLiveWatchUpdate: Hashable, Sendable {
    let state: PullRequestLiveWatchState
    let shouldReloadFocus: Bool
    let shouldRefreshSnapshot: Bool
    let shouldContinueWatching: Bool
}

struct PullRequestLiveWatchUpdateResult: Hashable, Sendable {
    let update: PullRequestLiveWatchUpdate
    let rateLimits: GitHubRateLimitSnapshot?
}

enum PullRequestLiveWatchPolicy {
    static func apply(
        previous: PullRequestLiveWatchState?,
        current: PullRequestLiveWatchState
    ) -> PullRequestLiveWatchUpdate {
        guard let previous else {
            return PullRequestLiveWatchUpdate(
                state: current,
                shouldReloadFocus: false,
                shouldRefreshSnapshot: false,
                shouldContinueWatching: current.resolution == .open
            )
        }

        let didChange =
            previous.resolution != current.resolution ||
            previous.isInMergeQueue != current.isInMergeQueue ||
            previous.headSHA != current.headSHA ||
            previous.latestTimelineMarker != current.latestTimelineMarker ||
            previous.detailsETag != current.detailsETag ||
            previous.timelineETag != current.timelineETag

        return PullRequestLiveWatchUpdate(
            state: current,
            shouldReloadFocus: didChange,
            shouldRefreshSnapshot:
                previous.resolution != current.resolution ||
                previous.isInMergeQueue != current.isInMergeQueue,
            shouldContinueWatching: current.resolution == .open
        )
    }
}

struct GitHubSubjectResolutionState: Hashable, Sendable {
    let reference: GitHubSubjectReference
    let resolution: GitHubSubjectResolution
    let isAssignedToViewer: Bool?
    let mergedAt: Date?
    let mergeCommitSHA: String?

    init(
        reference: GitHubSubjectReference,
        resolution: GitHubSubjectResolution,
        isAssignedToViewer: Bool?,
        mergedAt: Date? = nil,
        mergeCommitSHA: String? = nil
    ) {
        self.reference = reference
        self.resolution = resolution
        self.isAssignedToViewer = isAssignedToViewer
        self.mergedAt = mergedAt
        self.mergeCommitSHA = mergeCommitSHA
    }
}

struct AttentionTransitionNotification: Hashable, Sendable {
    let id: String
    let subjectKey: String?
    let title: String
    let subtitle: String
    let body: String
    let url: URL
}

struct PostMergeWatch: Identifiable, Hashable, Codable, Sendable {
    let reference: PullRequestReference
    let title: String
    let repository: String
    let url: URL
    let createdAt: Date
    let queuedAt: Date?
    let mergedAt: Date?
    let mergeCommitSHA: String?
    let lastObservedWorkflowRunAt: Date?
    let notifiedWorkflowRunIDs: [Int]
    let notifiedApprovalRequiredWorkflowRunIDs: [Int]?
    let suppressedWorkflowItemIDs: [String]

    var id: String { reference.pullRequestURL.absoluteString }

    func updating(
        mergedAt: Date? = nil,
        mergeCommitSHA: String? = nil,
        lastObservedWorkflowRunAt: Date? = nil,
        notifiedWorkflowRunIDs: [Int]? = nil,
        notifiedApprovalRequiredWorkflowRunIDs: [Int]? = nil,
        suppressedWorkflowItemIDs: [String]? = nil
    ) -> PostMergeWatch {
        PostMergeWatch(
            reference: reference,
            title: title,
            repository: repository,
            url: url,
            createdAt: createdAt,
            queuedAt: queuedAt,
            mergedAt: mergedAt ?? self.mergedAt,
            mergeCommitSHA: mergeCommitSHA ?? self.mergeCommitSHA,
            lastObservedWorkflowRunAt: lastObservedWorkflowRunAt ?? self.lastObservedWorkflowRunAt,
            notifiedWorkflowRunIDs: notifiedWorkflowRunIDs ?? self.notifiedWorkflowRunIDs,
            notifiedApprovalRequiredWorkflowRunIDs:
                notifiedApprovalRequiredWorkflowRunIDs ?? self.notifiedApprovalRequiredWorkflowRunIDs,
            suppressedWorkflowItemIDs: suppressedWorkflowItemIDs ?? self.suppressedWorkflowItemIDs
        )
    }

    static func register(
        item: AttentionItem,
        outcome: PullRequestMutationOutcome,
        at date: Date = .now
    ) -> PostMergeWatch? {
        guard let reference = item.pullRequestReference else {
            return nil
        }

        return PostMergeWatch(
            reference: reference,
            title: item.title,
            repository: item.repository ?? reference.repository,
            url: item.url,
            createdAt: date,
            queuedAt: outcome == .queued ? date : nil,
            mergedAt: outcome == .merged ? date : nil,
            mergeCommitSHA: nil,
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: [],
            suppressedWorkflowItemIDs: []
        )
    }

    static func registerResolved(
        item: AttentionItem,
        mergedAt: Date?,
        mergeCommitSHA: String?,
        at date: Date = .now
    ) -> PostMergeWatch? {
        guard let reference = item.pullRequestReference else {
            return nil
        }

        return PostMergeWatch(
            reference: reference,
            title: item.title,
            repository: item.repository ?? reference.repository,
            url: item.url,
            createdAt: date,
            queuedAt: nil,
            mergedAt: mergedAt ?? date,
            mergeCommitSHA: mergeCommitSHA,
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: [],
            suppressedWorkflowItemIDs: []
        )
    }
}

struct PostMergeObservedWorkflowRun: Hashable, Sendable {
    let id: Int
    let workflowID: Int?
    let title: String
    let repository: String
    let url: URL
    let event: String
    let status: String?
    let conclusion: String?
    let requiresApproval: Bool
    let createdAt: Date
    let actor: AttentionActor?

    var attentionItemID: String {
        "\(repository)-\(id)"
    }
}

struct PostMergeWatchObservation: Hashable, Sendable {
    let resolution: GitHubSubjectResolution
    let mergedAt: Date?
    let mergeCommitSHA: String?
    let workflowRuns: [PostMergeObservedWorkflowRun]
}

struct PostMergeWatchObservationResult: Hashable, Sendable {
    let observation: PostMergeWatchObservation
    let rateLimits: GitHubRateLimitSnapshot?
}

struct PostMergeWatchUpdate: Hashable, Sendable {
    let updatedWatch: PostMergeWatch?
    let notifications: [AttentionTransitionNotification]
}

enum PostMergeWatchRefreshPolicy {
    static func shouldRefreshSnapshot(
        watch: PostMergeWatch,
        observation: PostMergeWatchObservation
    ) -> Bool {
        guard watch.queuedAt != nil, watch.mergedAt == nil else {
            return false
        }

        return observation.resolution != .open
    }
}

enum PostMergeWatchPolicy {
    static func apply(
        watch: PostMergeWatch,
        observation: PostMergeWatchObservation,
        now: Date = .now
    ) -> PostMergeWatchUpdate {
        switch observation.resolution {
        case .closed:
            return PostMergeWatchUpdate(updatedWatch: nil, notifications: [])

        case .open:
            return PostMergeWatchUpdate(
                updatedWatch: shouldKeep(watch: watch, hasPendingRuns: false, now: now) ? watch : nil,
                notifications: []
            )

        case .merged:
            var updatedWatch = watch.updating(
                mergedAt: observation.mergedAt ?? watch.mergedAt ?? now,
                mergeCommitSHA: observation.mergeCommitSHA
            )
            var notifications = [AttentionTransitionNotification]()

            if watch.queuedAt != nil && watch.mergedAt == nil {
                notifications.append(
                    AttentionTransitionNotification(
                        id: "post-merge:merged:\(watch.id)",
                        subjectKey: watch.reference.pullRequestURL.absoluteString,
                        title: "Pull request merged",
                        subtitle: watch.title,
                        body: "Your queued pull request was merged in \(watch.repository).",
                        url: watch.url
                    )
                )
            }

            let pushRuns = observation.workflowRuns
                .filter { $0.event.caseInsensitiveCompare("push") == .orderedSame }
                .sorted { $0.createdAt < $1.createdAt }
            let hasPendingPushRuns = pushRuns.contains {
                ($0.status ?? "").caseInsensitiveCompare("completed") != .orderedSame
            }

            if let latestRunAt = pushRuns.map(\.createdAt).max() {
                updatedWatch = updatedWatch.updating(lastObservedWorkflowRunAt: latestRunAt)
            }

            var notifiedRunIDs = Set(updatedWatch.notifiedWorkflowRunIDs)
            var notifiedApprovalRequiredRunIDs = Set(
                updatedWatch.notifiedApprovalRequiredWorkflowRunIDs ?? []
            )
            var suppressedItemIDs = Set(updatedWatch.suppressedWorkflowItemIDs)

            for run in pushRuns {
                if
                    workflowRequiresApproval(run),
                    !notifiedApprovalRequiredRunIDs.contains(run.id),
                    let notification = workflowApprovalRequiredNotification(
                        for: run,
                        pullRequestTitle: watch.title,
                        subjectKey: watch.reference.pullRequestURL.absoluteString
                    )
                {
                    notifications.append(notification)
                    notifiedApprovalRequiredRunIDs.insert(run.id)
                    suppressedItemIDs.insert(run.attentionItemID)
                }

                guard
                    (run.status ?? "").caseInsensitiveCompare("completed") == .orderedSame,
                    !notifiedRunIDs.contains(run.id),
                    let notification = workflowCompletionNotification(
                        for: run,
                        pullRequestTitle: watch.title,
                        subjectKey: watch.reference.pullRequestURL.absoluteString,
                        hasPendingRuns: hasPendingPushRuns
                    )
                else {
                    continue
                }

                notifications.append(notification)
                notifiedRunIDs.insert(run.id)
                suppressedItemIDs.insert(run.attentionItemID)
            }

            updatedWatch = updatedWatch.updating(
                notifiedWorkflowRunIDs: Array(notifiedRunIDs).sorted(),
                notifiedApprovalRequiredWorkflowRunIDs:
                    Array(notifiedApprovalRequiredRunIDs).sorted(),
                suppressedWorkflowItemIDs: Array(suppressedItemIDs).sorted()
            )

            if shouldKeep(
                watch: updatedWatch,
                hasPendingRuns: hasPendingPushRuns,
                now: now
            ) {
                return PostMergeWatchUpdate(updatedWatch: updatedWatch, notifications: notifications)
            }

            return PostMergeWatchUpdate(updatedWatch: nil, notifications: notifications)
        }
    }

    static func shouldKeep(
        watch: PostMergeWatch,
        hasPendingRuns: Bool,
        now: Date = .now
    ) -> Bool {
        if watch.mergedAt == nil {
            return now.timeIntervalSince(watch.createdAt) < 86_400
        }

        if hasPendingRuns {
            return true
        }

        if let lastObservedWorkflowRunAt = watch.lastObservedWorkflowRunAt {
            return now.timeIntervalSince(lastObservedWorkflowRunAt) < 900
        }

        if let mergedAt = watch.mergedAt {
            return now.timeIntervalSince(mergedAt) < 1_800
        }

        return false
    }

    private static func workflowCompletionNotification(
        for run: PostMergeObservedWorkflowRun,
        pullRequestTitle: String,
        subjectKey: String,
        hasPendingRuns: Bool
    ) -> AttentionTransitionNotification? {
        let normalizedConclusion = (run.conclusion ?? "").lowercased()
        let title: String
        let body: String

        switch normalizedConclusion {
        case "success":
            guard !hasPendingRuns else {
                return nil
            }
            title = "Post-merge workflow succeeded"
            body = "\(run.title) finished successfully for \(pullRequestTitle)."
        case "failure", "timed_out", "startup_failure":
            title = "Post-merge workflow failed"
            body = "\(run.title) failed after \(pullRequestTitle) merged."
        default:
            return nil
        }

        return AttentionTransitionNotification(
            id: "post-merge:workflow:\(run.repository):\(run.id)",
            subjectKey: subjectKey,
            title: title,
            subtitle: run.title,
            body: body,
            url: run.url
        )
    }

    private static func workflowRequiresApproval(_ run: PostMergeObservedWorkflowRun) -> Bool {
        if run.requiresApproval {
            return true
        }

        let normalizedStatus = (run.status ?? "").lowercased()
        let normalizedConclusion = (run.conclusion ?? "").lowercased()

        return normalizedStatus == "action_required" || normalizedConclusion == "action_required"
    }

    private static func workflowApprovalRequiredNotification(
        for run: PostMergeObservedWorkflowRun,
        pullRequestTitle: String,
        subjectKey: String
    ) -> AttentionTransitionNotification? {
        guard workflowRequiresApproval(run) else {
            return nil
        }

        return AttentionTransitionNotification(
            id: "post-merge:workflow-approval:\(run.repository):\(run.id)",
            subjectKey: subjectKey,
            title: "Workflow waiting for approval",
            subtitle: run.title,
            body: "\(run.title) is waiting for approval for \(pullRequestTitle).",
            url: run.url
        )
    }
}

enum AttentionRemovalNotificationPolicy {
    static func notification(
        for removedItems: [AttentionItem],
        state: GitHubSubjectResolutionState
    ) -> AttentionTransitionNotification? {
        guard let representative = removedItems.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }

        switch state.resolution {
        case .merged:
            guard removedItems.contains(where: \.isClosureNotificationEligible) else {
                return nil
            }

            let body: String
            if removedItems.contains(where: { $0.type == .readyToMerge }) {
                body = "Your pull request was merged in \(representative.repository ?? state.reference.repository)."
            } else {
                body = "A pull request you were following was merged in \(representative.repository ?? state.reference.repository)."
            }

            return AttentionTransitionNotification(
                id: "resolved:merged:\(representative.ignoreKey)",
                subjectKey: state.reference.webURL.absoluteString,
                title: "Pull request merged",
                subtitle: representative.title,
                body: body,
                url: state.reference.webURL
            )

        case .closed:
            guard removedItems.contains(where: \.isClosureNotificationEligible) else {
                return nil
            }

            let title = state.reference.kind == .issue ? "Issue closed" : "Pull request closed"
            let body: String
            if state.reference.kind == .issue {
                body = "An issue you were following was closed in \(representative.repository ?? state.reference.repository)."
            } else {
                body = "A pull request you were following was closed in \(representative.repository ?? state.reference.repository)."
            }

            return AttentionTransitionNotification(
                id: "resolved:closed:\(representative.ignoreKey)",
                subjectKey: state.reference.webURL.absoluteString,
                title: title,
                subtitle: representative.title,
                body: body,
                url: state.reference.webURL
            )

        case .open:
            guard
                removedItems.contains(where: { $0.type == .assignedPullRequest }),
                state.reference.kind == .pullRequest,
                state.isAssignedToViewer == false
            else {
                return nil
            }

            return AttentionTransitionNotification(
                id: "resolved:unassigned:\(representative.ignoreKey)",
                subjectKey: state.reference.webURL.absoluteString,
                title: "Pull request unassigned",
                subtitle: representative.title,
                body: "This pull request is no longer assigned to you in \(representative.repository ?? state.reference.repository).",
                url: state.reference.webURL
            )
        }
    }
}

enum AttentionRemovalPostMergeWatchPolicy {
    static func watch(
        for removedItems: [AttentionItem],
        state: GitHubSubjectResolutionState,
        now: Date = .now
    ) -> PostMergeWatch? {
        guard
            state.reference.kind == .pullRequest,
            state.resolution == .merged
        else {
            return nil
        }

        let eligibleItems = removedItems.filter(\.isPostMergeWatchEligible)
        guard
            let representative = eligibleItems.max(by: { $0.timestamp < $1.timestamp })
        else {
            return nil
        }

        return PostMergeWatch.registerResolved(
            item: representative,
            mergedAt: state.mergedAt,
            mergeCommitSHA: state.mergeCommitSHA,
            at: now
        )
    }
}

enum PullRequestFocusMode: String, Hashable, Sendable {
    case authored
    case participating
    case generic

    var summary: String {
        switch self {
        case .authored:
            return "Prioritize unresolved conversations first, then failing checks."
        case .participating:
            return "Prioritize your open threads first, then changes since your review."
        case .generic:
            return "Showing the most actionable pull request signals available."
        }
    }
}

enum PullRequestFocusEntryAccent: String, Hashable, Sendable {
    case neutral
    case warning
    case failure
    case success
    case resolved
    case change
}

struct PullRequestFocusEntry: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String?
    let metadata: String?
    let timestamp: Date?
    let iconName: String
    let accent: PullRequestFocusEntryAccent
    let url: URL?
}

struct PullRequestFocusSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [PullRequestFocusEntry]
}

struct PullRequestFocus: Hashable, Sendable {
    let reference: PullRequestReference
    let baseBranch: String
    let sourceType: AttentionItemType
    let mode: PullRequestFocusMode
    let resolution: GitHubSubjectResolution
    let mergedAt: Date?
    let author: AttentionActor?
    let labels: [GitHubLabel]
    let headerFacts: [PullRequestHeaderFact]
    let contextBadges: [PullRequestContextBadge]
    let descriptionHTML: String?
    let statusSummary: PullRequestStatusSummary?
    let postMergeWorkflowPreview: PullRequestPostMergeWorkflowPreview?
    let sections: [PullRequestFocusSection]
    let timeline: [PullRequestTimelineEntry]
    let actions: [AttentionAction]
    let readyForReviewAction: PullRequestReadyForReviewAction?
    let reviewMergeAction: PullRequestReviewMergeAction?
    let emptyStateTitle: String
    let emptyStateDetail: String

    func displayedContextBadges(
        excluding currentSourceType: AttentionItemType
    ) -> [PullRequestContextBadge] {
        if currentSourceType == sourceType || postMergeWorkflowPreview == nil {
            return contextBadges
        }

        return PullRequestContextBadge.badges(
            workflowAttentionType: postMergeWorkflowPreview?.attentionType,
            excluding: currentSourceType
        )
    }
}

enum AttentionItemPresentationPolicy {
    static func sidebarContext(for item: AttentionItem) -> String {
        let typeSummary = item.type.nativeNotificationTitle
        let draftPrefix =
            item.pullRequestReference != nil && item.isDraft == true
            ? "Draft · "
            : ""

        if let repository = item.repository {
            return "\(repository) · \(draftPrefix)\(typeSummary)"
        }

        return "\(draftPrefix)\(typeSummary)"
    }
}

struct PullRequestTimelineEntry: Identifiable, Hashable, Sendable {
    let id: String
    let kind: Kind
    let author: AttentionActor?
    let bodyHTML: String?
    let timestamp: Date
    let url: URL?

    enum Kind: Hashable, Sendable {
        case comment
        case review(state: String)
        case reviewThread(
            path: String?,
            line: Int?,
            isResolved: Bool,
            isOutdated: Bool,
            comments: [PullRequestTimelineThreadComment]
        )
    }
}

struct PullRequestTimelineThreadComment: Identifiable, Hashable, Sendable {
    let id: String
    let author: AttentionActor?
    let bodyHTML: String?
    let timestamp: Date
    let url: URL?
    let isOutdated: Bool
    let isViewerAuthor: Bool
}

enum PullRequestPostMergeWorkflowStatus: Hashable, Sendable {
    case expected
    case waiting
    case queued
    case inProgress
    case actionRequired
    case succeeded
    case failed
    case completed(String)

    static func observed(
        status: String?,
        conclusion: String?,
        requiresApproval: Bool = false
    ) -> PullRequestPostMergeWorkflowStatus {
        let normalizedStatus = (status ?? "").lowercased()
        let normalizedConclusion = (conclusion ?? "").lowercased()

        if requiresApproval {
            return .actionRequired
        }

        if normalizedStatus == "action_required" || normalizedConclusion == "action_required" {
            return .actionRequired
        }

        if normalizedStatus != "completed" {
            switch normalizedStatus {
            case "queued", "requested", "pending", "waiting":
                return .queued
            default:
                return .inProgress
            }
        }

        switch normalizedConclusion {
        case "success":
            return .succeeded
        case "failure", "timed_out", "startup_failure":
            return .failed
        case "cancelled":
            return .completed("Cancelled")
        case "skipped":
            return .completed("Skipped")
        case "neutral":
            return .completed("Completed")
        default:
            return .completed("Completed")
        }
    }

    var label: String {
        switch self {
        case .expected:
            return "Will run on merge"
        case .waiting:
            return "No run observed yet"
        case .queued:
            return "Queued"
        case .inProgress:
            return "Running"
        case .actionRequired:
            return "Waiting for approval"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case let .completed(label):
            return label
        }
    }

    var iconName: String {
        switch self {
        case .expected, .waiting:
            return "arrow.triangle.branch"
        case .queued:
            return "clock"
        case .inProgress:
            return "hourglass"
        case .actionRequired:
            return "hand.raised"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .completed:
            return "checkmark.circle"
        }
    }

    var accent: PullRequestFocusEntryAccent {
        switch self {
        case .expected, .waiting:
            return .neutral
        case .queued, .inProgress, .actionRequired:
            return .warning
        case .succeeded:
            return .success
        case .failed:
            return .failure
        case .completed:
            return .resolved
        }
    }
}

enum PullRequestPostMergeWorkflowPreviewMode: Hashable, Sendable {
    case predicted(branch: String)
    case observed(branch: String)
}

struct PullRequestPostMergeWorkflowPreview: Hashable, Sendable {
    let mode: PullRequestPostMergeWorkflowPreviewMode
    let workflows: [PullRequestPostMergeWorkflow]
    let evaluationIssues: [PullRequestPostMergeWorkflowEvaluationIssue]

    var attentionType: AttentionItemType? {
        if workflows.contains(where: { $0.status == .failed }) {
            return .workflowFailed
        }

        if workflows.contains(where: { $0.status == .actionRequired }) {
            return .workflowApprovalRequired
        }

        return nil
    }

    var title: String {
        let singularTitle: String
        let pluralTitle: String

        switch mode {
        case .predicted:
            singularTitle = "Will run on merge"
            pluralTitle = "Will run on merge"
        case .observed:
            singularTitle = "Post-merge workflow"
            pluralTitle = "Post-merge workflows"
        }

        return workflows.count == 1 ? singularTitle : pluralTitle
    }

    var detail: String {
        let branch: String
        switch mode {
        case let .predicted(value), let .observed(value):
            branch = value
        }

        switch mode {
        case .predicted:
            return "These workflows should run when this pull request merges into \(branch)."
        case .observed:
            return "Tracking the workflows GitHub observed for the merge into \(branch)."
        }
    }

    var footnote: String? {
        guard !evaluationIssues.isEmpty else {
            return nil
        }

        return "Some workflow files could not be evaluated, so this list may be incomplete."
    }

    var footnoteHelpText: String? {
        guard !evaluationIssues.isEmpty else {
            return nil
        }

        return evaluationIssues.map(\.helpText).joined(separator: "\n")
    }
}

struct PullRequestPostMergeWorkflow: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let url: URL
    let status: PullRequestPostMergeWorkflowStatus
    let timestamp: Date?

    var workflowApprovalTarget: WorkflowApprovalTarget? {
        guard status == .actionRequired else {
            return nil
        }

        return WorkflowApprovalTarget(url: url)
    }
}

enum PullRequestFocusSupplementalItemPolicy {
    static func workflowItems(
        reference: PullRequestReference,
        title: String,
        repository: String,
        labels: [GitHubLabel],
        resolution: GitHubSubjectResolution,
        preview: PullRequestPostMergeWorkflowPreview?
    ) -> [AttentionItem] {
        guard let preview else {
            return []
        }

        return preview.workflows.compactMap { workflow in
            guard
                let type = actionableAttentionType(for: workflow.status),
                let timestamp = workflow.timestamp
            else {
                return nil
            }

            let repositoryURL = URL(string: "https://github.com/\(repository)")
            let subjectURL = reference.pullRequestURL
            let runIdentifier = workflowRunIdentifier(from: workflow.url) ?? workflow.id

            return AttentionItem(
                id: "\(AttentionSubjectRefresh.localSupplementalItemIDPrefix)workflow:\(runIdentifier)",
                subjectKey: subjectURL.absoluteString,
                updateKey: "focus-supplemental:workflow:\(runIdentifier):\(type.rawValue):\(Int(timestamp.timeIntervalSince1970))",
                latestSourceID: "focus-supplemental:workflow:\(runIdentifier)",
                stream: .pullRequests,
                type: type,
                title: title,
                subtitle: repository,
                repository: repository,
                labels: labels,
                timestamp: timestamp,
                url: workflow.url,
                subjectResolution: resolution,
                detail: AttentionDetail(
                    why: AttentionWhy(
                        summary: whySummary(for: type),
                        detail: "This workflow activity was observed while loading the pull request detail."
                    ),
                    evidence: [
                        AttentionEvidence(
                            id: "run",
                            title: "Workflow run",
                            detail: workflow.title,
                            iconName: type.iconName,
                            url: workflow.url
                        ),
                        AttentionEvidence(
                            id: "repository",
                            title: "Repository",
                            detail: repository,
                            iconName: "shippingbox",
                            url: repositoryURL
                        ),
                        AttentionEvidence(
                            id: "subject",
                            title: "Related pull request",
                            detail: "#\(reference.number) · \(title)",
                            iconName: "arrow.triangle.pull",
                            url: subjectURL
                        )
                    ],
                    actions: [
                        AttentionAction(
                            id: "open-run",
                            title: "Open Workflow Run",
                            iconName: "bolt",
                            url: workflow.url,
                            isPrimary: true
                        ),
                        AttentionAction(
                            id: "open-pr",
                            title: "Open Pull Request",
                            iconName: "arrow.triangle.pull",
                            url: subjectURL
                        )
                    ],
                    acknowledgement: "Use the toolbar to mark this read or ignore it."
                )
            )
        }
    }

    private static func actionableAttentionType(
        for status: PullRequestPostMergeWorkflowStatus
    ) -> AttentionItemType? {
        switch status {
        case .actionRequired:
            return .workflowApprovalRequired
        case .failed:
            return .workflowFailed
        case .expected, .waiting, .queued, .inProgress, .succeeded, .completed:
            return nil
        }
    }

    private static func workflowRunIdentifier(from url: URL) -> String? {
        if let approvalTarget = WorkflowApprovalTarget(url: url) {
            return approvalTarget.id
        }

        let components = url.pathComponents
        guard
            let runsIndex = components.firstIndex(of: "runs"),
            runsIndex + 1 < components.count
        else {
            return nil
        }

        return components[runsIndex + 1]
    }

    private static func whySummary(for type: AttentionItemType) -> String {
        switch type {
        case .workflowApprovalRequired:
            return "A post-merge workflow is waiting for approval."
        case .workflowFailed:
            return "A post-merge workflow failed and likely needs intervention."
        default:
            return "A post-merge workflow needs attention."
        }
    }
}

struct WorkflowPendingEnvironment: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let reviewerSummary: String?
    let canApprove: Bool
}

struct WorkflowPendingDeploymentReview: Hashable, Sendable {
    let target: WorkflowApprovalTarget
    let environments: [WorkflowPendingEnvironment]

    var approvableEnvironmentIDs: [Int] {
        environments.filter(\.canApprove).map(\.id)
    }
}

enum WorkflowPendingDeploymentDecision: String, Sendable {
    case approved
    case rejected
}

struct WorkflowPendingDeploymentReviewResult: Hashable, Sendable {
    let review: WorkflowPendingDeploymentReview
    let rateLimits: GitHubRateLimitSnapshot?
}

struct WorkflowPendingDeploymentMutationResult: Hashable, Sendable {
    let rateLimits: GitHubRateLimitSnapshot?
}

struct PullRequestPostMergeWorkflowEvaluationIssue: Identifiable, Hashable, Sendable {
    let path: String
    let message: String

    var id: String {
        path + "\n" + message
    }

    var helpText: String {
        "\(path): \(message)"
    }
}

enum PullRequestMergeMethod: String, Hashable, Sendable {
    case merge
    case squash
    case rebase

    var buttonTitle: String {
        switch self {
        case .merge:
            return "Merge Pull Request"
        case .squash:
            return "Squash and Merge"
        case .rebase:
            return "Rebase and Merge"
        }
    }

    var selectorTitle: String {
        switch self {
        case .merge:
            return "Create merge commit"
        case .squash:
            return "Squash and merge"
        case .rebase:
            return "Rebase and merge"
        }
    }

    static func allowedMethods(
        allowMergeCommit: Bool,
        allowSquashMerge: Bool,
        allowRebaseMerge: Bool
    ) -> [PullRequestMergeMethod] {
        var methods = [PullRequestMergeMethod]()

        if allowMergeCommit {
            methods.append(.merge)
        }

        if allowSquashMerge {
            methods.append(.squash)
        }

        if allowRebaseMerge {
            methods.append(.rebase)
        }

        return methods
    }

    static func fromAPIValues(_ values: [String]) -> [PullRequestMergeMethod] {
        values.compactMap(Self.init(apiValue:))
    }

    init?(apiValue: String) {
        switch apiValue.lowercased() {
        case "merge":
            self = .merge
        case "squash":
            self = .squash
        case "rebase":
            self = .rebase
        default:
            return nil
        }
    }
}

enum PullRequestMutationOutcome: Hashable, Sendable {
    case merged
    case queued

    var buttonTitle: String {
        switch self {
        case .merged:
            return "Merged"
        case .queued:
            return "Queued to Merge"
        }
    }

    var iconName: String {
        switch self {
        case .merged:
            return "checkmark.circle.fill"
        case .queued:
            return "clock"
        }
    }
}

enum GitHubMergeQueuePolicy {
    static func shouldFallback(statusCode: Int, message: String) -> Bool {
        guard statusCode == 405 else {
            return false
        }

        let normalized = message.lowercased()
        return normalized.contains("merge queue") ||
            normalized.contains("changes must be made through the merge queue")
    }
}

struct PullRequestMutationResult: Sendable {
    let outcome: PullRequestMutationOutcome
    let mergeMethod: PullRequestMergeMethod?
    let rateLimits: GitHubRateLimitSnapshot?
}

struct PullRequestHeaderFact: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let actor: AttentionActor
    let additionalActorCount: Int

    var overflowLabel: String? {
        guard additionalActorCount > 0 else {
            return nil
        }

        let noun = additionalActorCount == 1 ? "person" : "people"
        return "and \(additionalActorCount) more \(noun)"
    }
}

struct PullRequestFocusResult: Sendable {
    let focus: PullRequestFocus
    let rateLimits: GitHubRateLimitSnapshot?
    let subjectRefresh: AttentionSubjectRefresh
}

enum WorkflowRunAttributionPolicy {
    static let mergedRunLeadingSkew: TimeInterval = 300
    static let mergedRunAssociationWindow: TimeInterval = 7_200

    static func shouldAssociate(
        runTitle: String?,
        workflowName: String?,
        event: String,
        createdAt: Date,
        mergedAt: Date?
    ) -> Bool {
        if isClearlyScheduled(
            runTitle: runTitle,
            workflowName: workflowName,
            event: event
        ) {
            return false
        }

        guard let mergedAt else {
            return true
        }

        return createdAt >= mergedAt.addingTimeInterval(-mergedRunLeadingSkew) &&
            createdAt <= mergedAt.addingTimeInterval(mergedRunAssociationWindow)
    }

    static func shouldRetainHistoricalUpdate(
        _ update: AttentionUpdate,
        mergedAt: Date?
    ) -> Bool {
        guard update.type.isWorkflowActivity else {
            return true
        }

        return shouldAssociate(
            runTitle: update.detail,
            workflowName: nil,
            event: "",
            createdAt: update.timestamp,
            mergedAt: mergedAt
        )
    }

    private static func isClearlyScheduled(
        runTitle: String?,
        workflowName: String?,
        event: String
    ) -> Bool {
        if event.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("schedule") == .orderedSame {
            return true
        }

        let normalizedTitles = [runTitle, workflowName]
            .compactMap {
                $0?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }

        return normalizedTitles.contains("scheduled")
    }
}

enum PullRequestHeaderTimestampPolicy {
    static func primaryTimestamp(
        resolution: GitHubSubjectResolution,
        itemTimestamp: Date,
        mergedAt: Date?
    ) -> Date {
        if resolution == .merged, let mergedAt {
            return mergedAt
        }

        return itemTimestamp
    }

    static func shouldShowLastUpdate(
        resolution: GitHubSubjectResolution,
        itemTimestamp: Date,
        mergedAt: Date?,
        referenceDate: Date
    ) -> Bool {
        guard
            resolution == .merged,
            let mergedAt,
            itemTimestamp.timeIntervalSince(mergedAt) > 60
        else {
            return false
        }

        return relativeTimestampText(for: itemTimestamp, referenceDate: referenceDate) !=
            relativeTimestampText(for: mergedAt, referenceDate: referenceDate)
    }

    private static func relativeTimestampText(
        for date: Date,
        referenceDate: Date
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

enum AttentionViewerPresentationPolicy {
    struct ActorPresentation: Hashable, Sendable {
        let label: String
        let showsBotBadge: Bool
    }

    struct UpdatePresentation: Hashable, Sendable {
        let actor: ActorPresentation?
        let detail: String?

        var hasVisibleContent: Bool {
            actor != nil || detail != nil
        }
    }

    static func actorLabel(
        for actor: AttentionActor,
        viewerLogin: String?
    ) -> String {
        guard
            let viewerLogin,
            actor.login.caseInsensitiveCompare(viewerLogin) == .orderedSame
        else {
            return actor.displayLogin
        }

        return "you"
    }

    static func actorPresentation(
        for actor: AttentionActor,
        viewerLogin: String?
    ) -> ActorPresentation {
        ActorPresentation(
            label: actorLabel(for: actor, viewerLogin: viewerLogin),
            showsBotBadge: actor.isBotAccount
        )
    }

    static func personalizing(
        _ text: String,
        viewerLogin: String?
    ) -> String {
        guard let viewerLogin, !viewerLogin.isEmpty else {
            return text
        }

        if text.caseInsensitiveCompare(viewerLogin) == .orderedSame {
            return "you"
        }

        let prefix = "\(viewerLogin) · "
        guard let range = text.range(
            of: prefix,
            options: [.anchored, .caseInsensitive]
        ) else {
            return text
        }

        return text.replacingCharacters(in: range, with: "you · ")
    }

    static func updatePresentation(
        actor: AttentionActor?,
        detail: String?,
        viewerLogin: String?
    ) -> UpdatePresentation {
        let personalizedDetail = normalizedDetail(
            detail.map { personalizing($0, viewerLogin: viewerLogin) }
        )

        guard let actor else {
            return UpdatePresentation(actor: nil, detail: personalizedDetail)
        }

        let actorPresentation = actorPresentation(for: actor, viewerLogin: viewerLogin)
        return UpdatePresentation(
            actor: actorPresentation,
            detail: removingActorPrefix(
                from: personalizedDetail,
                actor: actor,
                actorLabel: actorPresentation.label
            )
        )
    }

    static func updateDetailText(
        actor: AttentionActor?,
        detail: String?,
        viewerLogin: String?
    ) -> String? {
        let presentation = updatePresentation(
            actor: actor,
            detail: detail,
            viewerLogin: viewerLogin
        )

        if let actorPresentation = presentation.actor {
            guard let detail = presentation.detail else {
                return actorPresentation.label
            }

            return "\(actorPresentation.label) · \(detail)"
        }

        return presentation.detail
    }

    static func listContextSubtitle(
        subtitle: String,
        actor: AttentionActor?,
        repository: String?,
        viewerLogin: String?,
        hidesRepository: Bool
    ) -> String? {
        let presentation = updatePresentation(
            actor: actor,
            detail: subtitle,
            viewerLogin: viewerLogin
        )

        guard var detail = presentation.detail else {
            return nil
        }

        if hidesRepository, let repository = normalizedDetail(repository) {
            detail = detail
                .components(separatedBy: " · ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter {
                    !$0.isEmpty &&
                        $0.caseInsensitiveCompare(repository) != .orderedSame
                }
                .joined(separator: " · ")
        }

        return normalizedDetail(detail)
    }

    private static func normalizedDetail(_ detail: String?) -> String? {
        guard let detail else {
            return nil
        }

        let normalized = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func removingActorPrefix(
        from detail: String?,
        actor: AttentionActor,
        actorLabel: String
    ) -> String? {
        guard let detail else {
            return nil
        }

        let candidates = [actorLabel, actor.displayLogin, actor.login]

        for candidate in candidates {
            if detail.caseInsensitiveCompare(candidate) == .orderedSame {
                return nil
            }

            let prefix = "\(candidate) · "
            if let range = detail.range(of: prefix, options: [.anchored, .caseInsensitive]) {
                let strippedDetail = String(detail[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return strippedDetail.isEmpty ? nil : strippedDetail
            }
        }

        return detail
    }
}

struct PullRequestContextBadge: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let iconName: String
    let accent: PullRequestFocusEntryAccent
}

struct PullRequestReviewMergeAction: Hashable, Sendable {
    static let mergeConflictsReason = "This pull request has merge conflicts with the base branch."

    let title: String
    let requiresApproval: Bool
    let isEnabled: Bool
    let disabledReason: String?
    let allowedMergeMethods: [PullRequestMergeMethod]
    let outcome: PullRequestMutationOutcome?

    var mergeMethod: PullRequestMergeMethod? {
        allowedMergeMethods.count == 1 ? allowedMergeMethods[0] : nil
    }

    var preferredMergeMethod: PullRequestMergeMethod? {
        allowedMergeMethods.first
    }

    var needsMergeMethodSelection: Bool {
        allowedMergeMethods.count > 1
    }

    var prioritizesBlockedStatusSummary: Bool {
        disabledReason == Self.mergeConflictsReason
    }

    var blockedStatusSummary: PullRequestStatusSummary? {
        guard let disabledReason, !isEnabled else {
            return nil
        }

        switch disabledReason {
        case "This pull request is still a draft.":
            return PullRequestStatusSummary(
                title: "Draft pull request",
                detail: disabledReason,
                iconName: "pencil.circle.fill",
                accent: .warning
            )
        case Self.mergeConflictsReason:
            return PullRequestStatusSummary(
                title: "Merge conflicts",
                detail: disabledReason,
                iconName: "arrow.triangle.branch",
                accent: .failure
            )
        case "GitHub does not consider this pull request mergeable yet.":
            return PullRequestStatusSummary(
                title: "Merge is blocked",
                detail: disabledReason,
                iconName: "arrow.triangle.branch",
                accent: .warning
            )
        case "Changes have been requested on this pull request.":
            return PullRequestStatusSummary(
                title: "Changes requested",
                detail: disabledReason,
                iconName: "exclamationmark.bubble.fill",
                accent: .failure
            )
        case "Resolve the open review conversations first.":
            return PullRequestStatusSummary(
                title: "Resolve conversations",
                detail: disabledReason,
                iconName: "bubble.left.and.exclamationmark.bubble.right.fill",
                accent: .warning
            )
        case "A review is still requested on this pull request.",
             "Reviews are still requested on this pull request.",
             "This pull request still needs an approving review.":
            return PullRequestStatusSummary(
                title: "Waiting on review",
                detail: disabledReason,
                iconName: "person.badge.key.fill",
                accent: .warning
            )
        case "You do not have permission to review and merge pull requests in this repository.",
             "You do not have permission to merge pull requests in this repository.":
            return PullRequestStatusSummary(
                title: "Merge unavailable",
                detail: disabledReason,
                iconName: "lock.circle.fill",
                accent: .warning
            )
        default:
            return PullRequestStatusSummary(
                title: "Merge unavailable",
                detail: disabledReason,
                iconName: "exclamationmark.circle.fill",
                accent: .warning
            )
        }
    }

    func applyingPreferredMergeMethod(_ mergeMethod: PullRequestMergeMethod?) -> PullRequestReviewMergeAction {
        PullRequestReviewMergeAction(
            title: title,
            requiresApproval: requiresApproval,
            isEnabled: isEnabled,
            disabledReason: disabledReason,
            allowedMergeMethods: PullRequestMergeMethodPolicy.prioritizing(
                mergeMethod,
                within: allowedMergeMethods
            ),
            outcome: outcome
        )
    }
}

struct PullRequestReadyForReviewAction: Hashable, Sendable {
    let title: String
    let isEnabled: Bool
    let disabledReason: String?

    static func makeAction(
        mode: PullRequestFocusMode,
        resolution: GitHubSubjectResolution,
        isDraft: Bool
    ) -> PullRequestReadyForReviewAction? {
        guard mode == .authored, resolution == .open, isDraft else {
            return nil
        }

        return PullRequestReadyForReviewAction(
            title: "Ready for Review",
            isEnabled: true,
            disabledReason: nil
        )
    }
}

enum PullRequestMergeMethodPolicy {
    static func effectiveAllowedMethods(
        repositoryAllowedMethods: [PullRequestMergeMethod],
        branchAllowedMethodGroups: [[PullRequestMergeMethod]],
        requiresLinearHistory: Bool
    ) -> [PullRequestMergeMethod] {
        var allowedMethodSet = Set(repositoryAllowedMethods)

        if let firstBranchAllowedMethods = branchAllowedMethodGroups.first {
            let branchIntersection = branchAllowedMethodGroups.dropFirst().reduce(
                Set(firstBranchAllowedMethods)
            ) { partialResult, methods in
                partialResult.intersection(methods)
            }
            allowedMethodSet.formIntersection(branchIntersection)
        }

        let orderedAllowedMethods = repositoryAllowedMethods.filter { allowedMethodSet.contains($0) }

        guard requiresLinearHistory else {
            return orderedAllowedMethods
        }

        return orderedAllowedMethods.filter { $0 != .merge }
    }

    static func prioritizing(
        _ mergeMethod: PullRequestMergeMethod?,
        within allowedMethods: [PullRequestMergeMethod]
    ) -> [PullRequestMergeMethod] {
        guard
            let mergeMethod,
            let existingIndex = allowedMethods.firstIndex(of: mergeMethod)
        else {
            return allowedMethods
        }

        var orderedMethods = allowedMethods
        orderedMethods.remove(at: existingIndex)
        orderedMethods.insert(mergeMethod, at: 0)
        return orderedMethods
    }
}

extension PullRequestFocus {
    func applyingPreferredMergeMethod(_ mergeMethod: PullRequestMergeMethod?) -> PullRequestFocus {
        PullRequestFocus(
            reference: reference,
            baseBranch: baseBranch,
            sourceType: sourceType,
            mode: mode,
            resolution: resolution,
            mergedAt: mergedAt,
            author: author,
            labels: labels,
            headerFacts: headerFacts,
            contextBadges: contextBadges,
            descriptionHTML: descriptionHTML,
            statusSummary: statusSummary,
            postMergeWorkflowPreview: postMergeWorkflowPreview,
            sections: sections,
            timeline: timeline,
            actions: actions,
            readyForReviewAction: readyForReviewAction,
            reviewMergeAction: reviewMergeAction?.applyingPreferredMergeMethod(mergeMethod),
            emptyStateTitle: emptyStateTitle,
            emptyStateDetail: emptyStateDetail
        )
    }

    func replacing(postMergeWorkflowPreview: PullRequestPostMergeWorkflowPreview?) -> PullRequestFocus {
        PullRequestFocus(
            reference: reference,
            baseBranch: baseBranch,
            sourceType: sourceType,
            mode: mode,
            resolution: resolution,
            mergedAt: mergedAt,
            author: author,
            labels: labels,
            headerFacts: headerFacts,
            contextBadges: contextBadges,
            descriptionHTML: descriptionHTML,
            statusSummary: statusSummary,
            postMergeWorkflowPreview: postMergeWorkflowPreview,
            sections: sections,
            timeline: timeline,
            actions: actions,
            readyForReviewAction: readyForReviewAction,
            reviewMergeAction: reviewMergeAction,
            emptyStateTitle: emptyStateTitle,
            emptyStateDetail: emptyStateDetail
        )
    }

    func restoringPostMergeWorkflowPreview(
        from previous: PullRequestFocus?
    ) -> PullRequestFocus {
        guard postMergeWorkflowPreview == nil else {
            return self
        }

        guard let previous, previous.reference == reference else {
            return self
        }

        return replacing(postMergeWorkflowPreview: previous.postMergeWorkflowPreview)
    }
}

enum PullRequestRepositoryPermissionPolicy {
    static func canMergeOrApprove(viewerPermission: String?) -> Bool {
        guard let viewerPermission else {
            return false
        }

        switch viewerPermission.uppercased() {
        case "ADMIN", "MAINTAIN", "WRITE":
            return true
        default:
            return false
        }
    }
}

enum PullRequestMergeQueuePolicy {
    static func shouldFallbackFromDirectMerge(statusCode: Int, message: String) -> Bool {
        guard statusCode == 405 else {
            return false
        }

        return message.localizedCaseInsensitiveContains("merge queue")
    }
}

struct PullRequestStatusSummary: Hashable, Sendable {
    let title: String
    let detail: String
    let iconName: String
    let accent: PullRequestFocusEntryAccent
}

struct PullRequestCheckSummary: Hashable, Sendable {
    let passedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let pendingCount: Int

    static let empty = PullRequestCheckSummary(
        passedCount: 0,
        skippedCount: 0,
        failedCount: 0,
        pendingCount: 0
    )

    var totalCount: Int {
        passedCount + skippedCount + failedCount + pendingCount
    }

    var hasFailures: Bool {
        failedCount > 0
    }

    var hasPending: Bool {
        pendingCount > 0
    }

    var isClear: Bool {
        !hasFailures && !hasPending
    }

    var detail: String {
        var segments = [String]()

        if failedCount > 0 {
            segments.append(Self.countLabel(failedCount, word: "failed"))
        }
        if pendingCount > 0 {
            segments.append(Self.countLabel(pendingCount, word: "pending"))
        }
        if passedCount > 0 {
            segments.append(Self.countLabel(passedCount, word: "passed"))
        }
        if skippedCount > 0 {
            segments.append(Self.countLabel(skippedCount, word: "skipped"))
        }

        if segments.isEmpty {
            return "No checks reported."
        }

        return segments.joined(separator: " · ")
    }

    private static func countLabel(_ count: Int, word: String) -> String {
        "\(count) \(word)"
    }
}

extension PullRequestContextBadge {
    static func badges(
        workflowAttentionType: AttentionItemType?,
        excluding sourceType: AttentionItemType? = nil
    ) -> [PullRequestContextBadge] {
        guard let workflowAttentionType, workflowAttentionType != sourceType else {
            return []
        }

        let accent: PullRequestFocusEntryAccent
        switch workflowAttentionType {
        case .workflowFailed:
            accent = .failure
        case .workflowApprovalRequired:
            accent = .warning
        default:
            accent = .neutral
        }

        return [
            PullRequestContextBadge(
                id: "workflow-attention",
                title: workflowAttentionType.accessibilityLabel,
                iconName: workflowAttentionType.iconName,
                accent: accent
            )
        ]
    }
}

extension PullRequestHeaderFact {
    static func build(
        sourceType: AttentionItemType,
        resolution: GitHubSubjectResolution,
        sourceActor: AttentionActor?,
        author: AttentionActor?,
        assigner: AttentionActor?,
        latestApprover: AttentionActor?,
        approvalCount: Int,
        mergedBy: AttentionActor?
    ) -> [PullRequestHeaderFact] {
        switch sourceType {
        case .readyToMerge:
            return authorApprovalFacts(
                author: author,
                approver: sourceActor ?? latestApprover,
                approvalOverflowCount: max(0, approvalCount - 1)
            )

        case .reviewApproved:
            return authorApprovalFacts(
                author: author,
                approver: sourceActor ?? latestApprover,
                approvalOverflowCount: 0
            )

        case .reviewComment:
            guard let sourceActor else {
                return []
            }

            return [
                PullRequestHeaderFact(
                    id: "commented-by",
                    label: "commented by",
                    actor: sourceActor,
                    additionalActorCount: 0
                )
            ]

        case .reviewChangesRequested:
            guard let sourceActor else {
                return []
            }

            return [
                PullRequestHeaderFact(
                    id: "changes-requested-by",
                    label: "changes requested by",
                    actor: sourceActor,
                    additionalActorCount: 0
                )
            ]

        default:
            break
        }

        if resolution == .merged {
            var facts = [PullRequestHeaderFact]()

            if sourceType == .authoredPullRequest, let latestApprover {
                facts.append(
                    PullRequestHeaderFact(
                        id: "approved-by",
                        label: "approved by",
                        actor: latestApprover,
                        additionalActorCount: max(0, approvalCount - 1)
                    )
                )
            }

            if let mergedBy {
                facts.append(
                    PullRequestHeaderFact(
                        id: "merged-by",
                        label: "merged by",
                        actor: mergedBy,
                        additionalActorCount: 0
                    )
                )
            }

            if !facts.isEmpty {
                return facts
            }
        }

        switch sourceType {
        case .assignedPullRequest:
            if let author, let assigner, author.isSameAccount(as: assigner) {
                return [
                    PullRequestHeaderFact(
                        id: "created-and-assigned-by",
                        label: "created and assigned by",
                        actor: author,
                        additionalActorCount: 0
                    )
                ]
            }

            var facts = [PullRequestHeaderFact]()

            if let author {
                facts.append(
                    PullRequestHeaderFact(
                        id: "created-by",
                        label: "created by",
                        actor: author,
                        additionalActorCount: 0
                    )
                )
            }

            if let assigner {
                facts.append(
                    PullRequestHeaderFact(
                        id: "assigned-by",
                        label: "assigned by",
                        actor: assigner,
                        additionalActorCount: 0
                    )
                )
            }

            return facts

        case .authoredPullRequest:
            return []

        default:
            guard let author else {
                return []
            }

            return [
                PullRequestHeaderFact(
                    id: "created-by",
                    label: "created by",
                    actor: author,
                    additionalActorCount: 0
                )
            ]
        }
    }

    private static func authorApprovalFacts(
        author: AttentionActor?,
        approver: AttentionActor?,
        approvalOverflowCount: Int
    ) -> [PullRequestHeaderFact] {
        if let author, let approver, author.isSameAccount(as: approver) {
            return [
                PullRequestHeaderFact(
                    id: "created-and-approved-by",
                    label: "created and approved by",
                    actor: author,
                    additionalActorCount: approvalOverflowCount
                )
            ]
        }

        var facts = [PullRequestHeaderFact]()

        if let author {
            facts.append(
                PullRequestHeaderFact(
                    id: "created-by",
                    label: "created by",
                    actor: author,
                    additionalActorCount: 0
                )
            )
        }

        if let approver {
            facts.append(
                PullRequestHeaderFact(
                    id: "approved-by",
                    label: "approved by",
                    actor: approver,
                    additionalActorCount: approvalOverflowCount
                )
            )
        }

        return facts
    }
}

enum TrackedSubjectAttentionPolicy {
    static func shouldReplace(existing: AttentionItemType, with candidate: AttentionItemType) -> Bool {
        priority(for: candidate) > priority(for: existing)
    }

    private static func priority(for type: AttentionItemType) -> Int {
        switch type {
        case .authoredPullRequest:
            return 3
        case .reviewedPullRequest:
            return 2
        case .commentedPullRequest:
            return 1
        case .assignedIssue:
            return 3
        case .authoredIssue:
            return 2
        case .commentedIssue:
            return 1
        default:
            return 0
        }
    }
}

extension PullRequestReviewMergeAction {
    static func makeAction(
        sourceType: AttentionItemType,
        mode: PullRequestFocusMode,
        author: AttentionActor?,
        viewerPermission: String?,
        allowMergeCommit: Bool,
        allowSquashMerge: Bool,
        allowRebaseMerge: Bool,
        preferredMergeMethod: PullRequestMergeMethod? = nil,
        mergeable: String?,
        isDraft: Bool,
        reviewDecision: String?,
        approvalCount: Int,
        hasChangesRequested: Bool,
        pendingReviewRequestCount: Int,
        checkSummary: PullRequestCheckSummary,
        openThreadCount: Int,
        isMerged: Bool = false,
        isInMergeQueue: Bool = false
    ) -> PullRequestReviewMergeAction? {
        let isBotReviewablePullRequest =
            author?.isBotAccount == true && mode != .authored
        let isMergeCandidateFromYourPullRequest = mode == .authored

        guard isBotReviewablePullRequest || isMergeCandidateFromYourPullRequest else {
            return nil
        }

        let hasApproval = reviewDecision?.caseInsensitiveCompare("APPROVED") == .orderedSame ||
            approvalCount > 0
        let requiresApproval = isBotReviewablePullRequest && !hasApproval
        let title = requiresApproval ? "Approve and Merge" : "Merge Pull Request"
        let allowsCurrentReviewRequestToBeSatisfied =
            requiresApproval && pendingReviewRequestCount == 1
        let allowedMergeMethods = PullRequestMergeMethodPolicy.prioritizing(
            preferredMergeMethod,
            within: PullRequestMergeMethod.allowedMethods(
                allowMergeCommit: allowMergeCommit,
                allowSquashMerge: allowSquashMerge,
                allowRebaseMerge: allowRebaseMerge
            )
        )

        if isMerged {
            return PullRequestReviewMergeAction(
                title: PullRequestMutationOutcome.merged.buttonTitle,
                requiresApproval: false,
                isEnabled: false,
                disabledReason: nil,
                allowedMergeMethods: [],
                outcome: .merged
            )
        }

        if isInMergeQueue {
            return PullRequestReviewMergeAction(
                title: PullRequestMutationOutcome.queued.buttonTitle,
                requiresApproval: false,
                isEnabled: false,
                disabledReason: nil,
                allowedMergeMethods: [],
                outcome: .queued
            )
        }

        if !PullRequestRepositoryPermissionPolicy.canMergeOrApprove(viewerPermission: viewerPermission) {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: requiresApproval
                    ? "You do not have permission to review and merge pull requests in this repository."
                    : "You do not have permission to merge pull requests in this repository.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        if isDraft {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "This pull request is still a draft.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        if mergeable?.caseInsensitiveCompare("CONFLICTING") == .orderedSame {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: Self.mergeConflictsReason,
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        if mergeable?.caseInsensitiveCompare("MERGEABLE") != .orderedSame {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "GitHub does not consider this pull request mergeable yet.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        guard !allowedMergeMethods.isEmpty else {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "This repository does not allow pull requests to be merged directly.",
                allowedMergeMethods: [],
                outcome: nil
            )
        }

        if hasChangesRequested {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "Changes have been requested on this pull request.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        if pendingReviewRequestCount > 0 && !allowsCurrentReviewRequestToBeSatisfied {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: pendingReviewRequestCount == 1
                    ? "A review is still requested on this pull request."
                    : "Reviews are still requested on this pull request.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        if openThreadCount > 0 {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "Resolve the open review conversations first.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        if checkSummary.hasFailures {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "Some checks are failing.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        if checkSummary.hasPending {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "Checks are still running.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        if !requiresApproval && !hasApproval {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "This pull request still needs an approving review.",
                allowedMergeMethods: allowedMergeMethods,
                outcome: nil
            )
        }

        return PullRequestReviewMergeAction(
            title: title,
            requiresApproval: requiresApproval,
            isEnabled: true,
            disabledReason: nil,
            allowedMergeMethods: allowedMergeMethods,
            outcome: nil
        )
    }
}

extension AttentionAction {
    static func pullRequestActions(
        reference: PullRequestReference,
        mode: PullRequestFocusMode,
        checkSummary: PullRequestCheckSummary,
        hasNewCommits: Bool,
        hasPrimaryMutationAction: Bool
    ) -> [AttentionAction] {
        var actions = [AttentionAction]()

        actions.append(
            AttentionAction(
                id: "view-pr",
                title: "View on GitHub",
                iconName: "arrow.up.right.square",
                url: reference.pullRequestURL,
                isPrimary: !hasPrimaryMutationAction
            )
        )

        actions.append(
            AttentionAction(
                id: "open-files",
                title: "View Files",
                iconName: "doc.text",
                url: reference.filesURL
            )
        )

        if checkSummary.totalCount > 0 || mode == .authored {
            actions.append(
                AttentionAction(
                    id: "open-checks",
                    title: "Open Checks",
                    iconName: "checklist",
                    url: reference.checksURL
                )
            )
        }

        if hasNewCommits {
            actions.append(
                AttentionAction(
                    id: "open-commits",
                    title: mode == .participating ? "View New Commits" : "View Commits",
                    iconName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    url: reference.commitsURL
                )
            )
        }

        return actions
    }
}

extension PullRequestStatusSummary {
    static func build(
        mode: PullRequestFocusMode,
        resolution: GitHubSubjectResolution = .open,
        checkSummary: PullRequestCheckSummary,
        openThreadCount: Int,
        reviewMergeAction: PullRequestReviewMergeAction?,
        commitsSinceReview: [PullRequestFocusEntry] = []
    ) -> PullRequestStatusSummary? {
        switch resolution {
        case .merged:
            return PullRequestStatusSummary(
                title: "Merged",
                detail: "This pull request has already been merged.",
                iconName: "checkmark.circle.fill",
                accent: .resolved
            )
        case .closed:
            return PullRequestStatusSummary(
                title: "Closed",
                detail: "This pull request is already closed.",
                iconName: "xmark.circle.fill",
                accent: .warning
            )
        case .open:
            break
        }

        if let outcome = reviewMergeAction?.outcome {
            switch outcome {
            case .merged:
                return PullRequestStatusSummary(
                    title: "Merged",
                    detail: "This pull request has been merged.",
                    iconName: "checkmark.circle.fill",
                    accent: .resolved
                )
            case .queued:
                return PullRequestStatusSummary(
                    title: "Queued to merge",
                    detail: "This pull request is waiting in the merge queue.",
                    iconName: "clock",
                    accent: .warning
                )
            }
        }

        if reviewMergeAction?.prioritizesBlockedStatusSummary == true,
            let blockedSummary = reviewMergeAction?.blockedStatusSummary {
            return blockedSummary
        }

        if checkSummary.hasFailures {
            return PullRequestStatusSummary(
                title: checkSummary.failedCount == 1 ? "1 check failed" : "\(checkSummary.failedCount) checks failed",
                detail: checkSummary.detail,
                iconName: "xmark.octagon.fill",
                accent: .failure
            )
        }

        if checkSummary.hasPending {
            return PullRequestStatusSummary(
                title: "Checks still running",
                detail: checkSummary.detail,
                iconName: "clock.badge.exclamationmark",
                accent: .warning
            )
        }

        if let reviewMergeAction, reviewMergeAction.isEnabled {
            return PullRequestStatusSummary(
                title: reviewMergeAction.requiresApproval ? "Ready to approve and merge" : "Ready to merge",
                detail: checkSummary.totalCount > 0
                    ? checkSummary.detail
                    : "There are no unresolved conversations or failing checks.",
                iconName: "checkmark.circle.fill",
                accent: .success
            )
        }

        if let blockedSummary = reviewMergeAction?.blockedStatusSummary {
            return blockedSummary
        }

        if mode == .participating, !commitsSinceReview.isEmpty {
            let latestCommit = commitsSinceReview[0]
            let title = commitsSinceReview.count == 1
                ? "1 new commit since your review"
                : "\(commitsSinceReview.count) new commits since your review"
            let detail: String
            if checkSummary.totalCount > 0, checkSummary.isClear {
                detail = "Latest: \(latestCommit.title) · \(checkSummary.detail)"
            } else {
                detail = "Latest: \(latestCommit.title)"
            }

            return PullRequestStatusSummary(
                title: title,
                detail: detail,
                iconName: "arrow.trianglehead.branch",
                accent: .change
            )
        }

        if mode == .authored && openThreadCount == 0 {
            return PullRequestStatusSummary(
                title: "Checks look good",
                detail: checkSummary.totalCount > 0
                    ? checkSummary.detail
                    : "There are no unresolved conversations or failing checks.",
                iconName: "checkmark.circle",
                accent: .success
            )
        }

        if checkSummary.totalCount > 0 && checkSummary.isClear {
            return PullRequestStatusSummary(
                title: "Checks look good",
                detail: checkSummary.detail,
                iconName: "checkmark.circle",
                accent: .success
            )
        }

        return nil
    }
}

struct AttentionItem: Identifiable, Hashable, Sendable {
    let id: String
    let subjectKey: String
    let updateKey: String
    let latestSourceID: String
    let stream: AttentionStream
    let type: AttentionItemType
    let secondaryIndicatorType: AttentionItemType?
    let focusType: AttentionItemType?
    let focusActor: AttentionActor?
    let title: String
    let subtitle: String
    let repository: String?
    let labels: [GitHubLabel]
    let timestamp: Date
    let url: URL
    let actor: AttentionActor?
    let isTriggeredByCurrentUser: Bool
    let subjectResolution: GitHubSubjectResolution?
    let detail: AttentionDetail
    let currentUpdateTypes: Set<AttentionItemType>
    let currentRelationshipTypes: Set<AttentionItemType>
    let isHistoricalLogEntry: Bool
    let closureNotificationEligibleOverride: Bool?
    let postMergeWatchEligibleOverride: Bool?
    let isDraft: Bool?
    let supportsReadState: Bool
    var isUnread: Bool

    init(
        id: String,
        subjectKey: String,
        updateKey: String? = nil,
        latestSourceID: String? = nil,
        stream: AttentionStream? = nil,
        type: AttentionItemType,
        secondaryIndicatorType: AttentionItemType? = nil,
        focusType: AttentionItemType? = nil,
        focusActor: AttentionActor? = nil,
        title: String,
        subtitle: String,
        repository: String? = nil,
        labels: [GitHubLabel] = [],
        timestamp: Date,
        url: URL,
        actor: AttentionActor? = nil,
        isTriggeredByCurrentUser: Bool = false,
        subjectResolution: GitHubSubjectResolution? = nil,
        detail: AttentionDetail? = nil,
        currentUpdateTypes: Set<AttentionItemType>? = nil,
        currentRelationshipTypes: Set<AttentionItemType>? = nil,
        isHistoricalLogEntry: Bool = false,
        closureNotificationEligibleOverride: Bool? = nil,
        postMergeWatchEligibleOverride: Bool? = nil,
        isDraft: Bool? = nil,
        supportsReadState: Bool = true,
        isUnread: Bool = true
    ) {
        self.id = id
        self.subjectKey = subjectKey
        self.updateKey = updateKey ?? id
        self.latestSourceID = latestSourceID ?? id
        self.stream = stream ?? type.defaultStream
        self.type = type
        self.secondaryIndicatorType = secondaryIndicatorType
        self.focusType = focusType
        self.focusActor = focusActor
        self.title = title
        self.subtitle = subtitle
        self.repository = repository
        self.labels = labels
        self.timestamp = timestamp
        self.url = url
        self.actor = actor
        self.isTriggeredByCurrentUser = isTriggeredByCurrentUser
        self.subjectResolution = subjectResolution
        self.detail = detail ?? Self.defaultDetail(
            type: type,
            subtitle: subtitle,
            url: url,
            actor: actor
        )
        self.currentUpdateTypes = currentUpdateTypes ?? (
            type.isRelationshipType ? [] : [type]
        )
        self.currentRelationshipTypes = currentRelationshipTypes ?? (
            type.isRelationshipType ? [type] : []
        )
        self.isHistoricalLogEntry = isHistoricalLogEntry
        self.closureNotificationEligibleOverride = closureNotificationEligibleOverride
        self.postMergeWatchEligibleOverride = postMergeWatchEligibleOverride
        self.isDraft = isDraft
        self.supportsReadState = supportsReadState
        self.isUnread = isUnread
    }

    var ignoreKey: String { subjectKey }

    var pullRequestFocusSourceType: AttentionItemType {
        if let focusType, focusType.isRelationshipType {
            return focusType
        }

        if currentUpdateTypes.contains(.teamReviewRequested) {
            return .teamReviewRequested
        }

        if currentUpdateTypes.contains(.reviewRequested) {
            return .reviewRequested
        }

        if let focusType {
            return focusType
        }

        return type
    }

    func replacing(detail: AttentionDetail) -> AttentionItem {
        AttentionItem(
            id: id,
            subjectKey: subjectKey,
            updateKey: updateKey,
            latestSourceID: latestSourceID,
            stream: stream,
            type: type,
            secondaryIndicatorType: secondaryIndicatorType,
            focusType: focusType,
            focusActor: focusActor,
            title: title,
            subtitle: subtitle,
            repository: repository,
            labels: labels,
            timestamp: timestamp,
            url: url,
            actor: actor,
            isTriggeredByCurrentUser: isTriggeredByCurrentUser,
            subjectResolution: subjectResolution,
            detail: detail,
            currentUpdateTypes: currentUpdateTypes,
            currentRelationshipTypes: currentRelationshipTypes,
            isHistoricalLogEntry: isHistoricalLogEntry,
            closureNotificationEligibleOverride: closureNotificationEligibleOverride,
            postMergeWatchEligibleOverride: postMergeWatchEligibleOverride,
            isDraft: isDraft,
            supportsReadState: supportsReadState,
            isUnread: isUnread
        )
    }

    func replacing(labels: [GitHubLabel]) -> AttentionItem {
        AttentionItem(
            id: id,
            subjectKey: subjectKey,
            updateKey: updateKey,
            latestSourceID: latestSourceID,
            stream: stream,
            type: type,
            secondaryIndicatorType: secondaryIndicatorType,
            focusType: focusType,
            focusActor: focusActor,
            title: title,
            subtitle: subtitle,
            repository: repository,
            labels: labels,
            timestamp: timestamp,
            url: url,
            actor: actor,
            isTriggeredByCurrentUser: isTriggeredByCurrentUser,
            subjectResolution: subjectResolution,
            detail: detail,
            currentUpdateTypes: currentUpdateTypes,
            currentRelationshipTypes: currentRelationshipTypes,
            isHistoricalLogEntry: isHistoricalLogEntry,
            closureNotificationEligibleOverride: closureNotificationEligibleOverride,
            postMergeWatchEligibleOverride: postMergeWatchEligibleOverride,
            isDraft: isDraft,
            supportsReadState: supportsReadState,
            isUnread: isUnread
        )
    }

    var nativeNotificationTitle: String {
        guard let actor else {
            return type.nativeNotificationTitle
        }

        return "\(actor.login) \(type.actorVerb)"
    }

    var actorRelationshipLabel: String {
        switch type {
        case .readyToMerge, .reviewApproved:
            return "approved by"
        case .reviewComment, .comment:
            return "commented by"
        case .reviewChangesRequested:
            return "changes requested by"
        case .pullRequestMergeConflicts:
            return "conflicts reported by"
        case .pullRequestFailedChecks:
            return "checks reported by"
        default:
            if detail.contextPillTitle == PullRequestStateTransition.merged.title {
                return "merged by"
            }

            return "by"
        }
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

    var workflowApprovalURL: URL? {
        guard type == .workflowApprovalRequired || currentUpdateTypes.contains(.workflowApprovalRequired) else {
            return nil
        }

        if let updateURL = detail.updates.first(where: { $0.type == .workflowApprovalRequired })?.url {
            return updateURL
        }

        if type == .workflowApprovalRequired, WorkflowApprovalTarget(url: url) != nil {
            return url
        }

        return nil
    }

    var workflowApprovalTarget: WorkflowApprovalTarget? {
        workflowApprovalURL.flatMap(WorkflowApprovalTarget.init(url:))
    }

    var repositoryURL: URL? {
        guard let repository else {
            return nil
        }

        return URL(string: "https://github.com/\(repository)")
    }

    var pullRequestReference: PullRequestReference? {
        Self.pullRequestReference(from: ignoreKey) ??
            Self.pullRequestReference(from: url.absoluteString)
    }

    var subjectReference: GitHubSubjectReference? {
        Self.subjectReference(from: ignoreKey) ??
            Self.subjectReference(from: url.absoluteString)
    }

    func labelSearchURL(for label: GitHubLabel) -> URL? {
        subjectReference?.labelSearchURL(for: label)
    }

    var isClosureNotificationEligible: Bool {
        if let closureNotificationEligibleOverride {
            return closureNotificationEligibleOverride
        }

        switch type {
        case .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .readyToMerge,
                .pullRequestMergeConflicts,
                .pullRequestFailedChecks,
                .assignedIssue,
                .authoredIssue,
                .commentedIssue,
                .comment,
                .mention,
                .teamMention,
                .newCommitsAfterComment,
                .newCommitsAfterReview,
                .reviewApproved,
                .reviewChangesRequested,
                .reviewComment,
                .pullRequestStateChanged:
            return true
        case .assignedPullRequest,
                .reviewRequested,
                .teamReviewRequested,
                .securityAlert,
                .ciActivity,
                .workflowRunning,
                .workflowSucceeded,
                .workflowFailed,
                .workflowApprovalRequired:
            return false
        }
    }

    var isPostMergeWatchEligible: Bool {
        guard pullRequestReference != nil else {
            return false
        }

        if let postMergeWatchEligibleOverride {
            return postMergeWatchEligibleOverride
        }

        switch type {
        case .assignedPullRequest,
                .reviewRequested,
                .teamReviewRequested,
                .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .readyToMerge,
                .pullRequestMergeConflicts,
                .pullRequestFailedChecks,
                .securityAlert,
                .comment,
                .mention,
                .teamMention,
                .newCommitsAfterComment,
                .newCommitsAfterReview,
                .reviewApproved,
                .reviewChangesRequested,
                .reviewComment,
                .pullRequestStateChanged:
            return true
        case .assignedIssue,
                .authoredIssue,
                .commentedIssue,
                .ciActivity,
                .workflowRunning,
                .workflowSucceeded,
                .workflowFailed,
                .workflowApprovalRequired:
            return false
        }
    }

    private static func defaultDetail(
        type: AttentionItemType,
        subtitle: String,
        url: URL,
        actor: AttentionActor?
    ) -> AttentionDetail {
        let why = AttentionWhy(
            summary: defaultWhySummary(for: type),
            detail: subtitle
        )

        var evidence = [AttentionEvidence]()
        if !subtitle.isEmpty {
            evidence.append(
                AttentionEvidence(
                    id: "context",
                    title: "Current context",
                    detail: subtitle,
                    iconName: "info.circle"
                )
            )
        }

        if let actor {
            evidence.append(
                AttentionEvidence(
                    id: "actor",
                    title: "Triggered by",
                    detail: actor.login,
                    iconName: "person.crop.circle",
                    url: actor.isBotAccount ? nil : actor.profileURL
                )
            )
        }

        var actions = [
            AttentionAction(
                id: "open",
                title: "Open on GitHub",
                iconName: "arrow.up.right.square",
                url: url,
                isPrimary: true
            )
        ]

        if let actor, !actor.isBotAccount {
            actions.append(
                AttentionAction(
                    id: "actor-profile",
                    title: "Open \(actor.login)",
                    iconName: "person.crop.circle",
                    url: actor.profileURL
                )
            )
        }

        return AttentionDetail(
            why: why,
            evidence: evidence,
            actions: actions,
            acknowledgement: "Use the toolbar to mark this read or ignore it."
        )
    }

    private static func defaultWhySummary(for type: AttentionItemType) -> String {
        switch type {
        case .assignedPullRequest:
            return "This pull request is assigned to you."
        case .authoredPullRequest:
            return "You opened this pull request."
        case .reviewedPullRequest:
            return "You reviewed this pull request."
        case .commentedPullRequest:
            return "You commented on this pull request."
        case .readyToMerge:
            return "One of your pull requests is approved and ready to merge."
        case .pullRequestMergeConflicts:
            return "One of your pull requests now has merge conflicts."
        case .pullRequestFailedChecks:
            return "One of your pull requests has failing checks."
        case .assignedIssue:
            return "This issue is assigned to you."
        case .authoredIssue:
            return "You opened this issue."
        case .commentedIssue:
            return "You commented on this issue."
        case .securityAlert:
            return "GitHub detected a security alert for this repository."
        case .comment:
            return "There is new discussion on work you are following."
        case .mention:
            return "Someone mentioned you in a GitHub discussion."
        case .teamMention:
            return "One of your GitHub teams was mentioned in a discussion."
        case .newCommitsAfterComment:
            return "A pull request changed after you commented on it."
        case .newCommitsAfterReview:
            return "A pull request changed after you reviewed it."
        case .reviewRequested:
            return "A pull request is waiting for your review."
        case .teamReviewRequested:
            return "A pull request is waiting on one of your teams."
        case .reviewApproved:
            return "A pull request you are tracking was approved."
        case .reviewChangesRequested:
            return "A pull request you are tracking now has requested changes."
        case .reviewComment:
            return "A pull request you are tracking has new review feedback."
        case .pullRequestStateChanged:
            return "A pull request you are tracking changed state."
        case .ciActivity:
            return "GitHub Actions activity needs attention."
        case .workflowRunning:
            return "A workflow run is currently in progress."
        case .workflowSucceeded:
            return "A workflow run finished successfully."
        case .workflowFailed:
            return "A workflow run failed and likely needs intervention."
        case .workflowApprovalRequired:
            return "A workflow run is waiting for approval before it can continue."
        }
    }

    private static func pullRequestReference(from value: String) -> PullRequestReference? {
        guard let reference = subjectReference(from: value), reference.kind == .pullRequest else {
            return nil
        }

        return PullRequestReference(
            owner: reference.owner,
            name: reference.name,
            number: reference.number
        )
    }

    static func subjectReference(fromSubjectKey value: String) -> GitHubSubjectReference? {
        subjectReference(from: value)
    }

    private static func subjectReference(from value: String) -> GitHubSubjectReference? {
        guard let url = URL(string: value) else {
            return nil
        }

        let components = url.pathComponents
        guard components.count >= 5 else {
            return nil
        }

        guard let number = Int(components[4]) else {
            return nil
        }

        switch components[3] {
        case "pull":
            return GitHubSubjectReference(
                owner: components[1],
                name: components[2],
                number: number,
                kind: .pullRequest
            )
        case "issues":
            return GitHubSubjectReference(
                owner: components[1],
                name: components[2],
                number: number,
                kind: .issue
            )
        default:
            return nil
        }
    }
}

extension AttentionItemType {
    var isWorkflowActivityType: Bool {
        switch self {
        case .workflowRunning,
                .workflowSucceeded,
                .workflowFailed,
                .workflowApprovalRequired:
            return true
        default:
            return false
        }
    }

    var isRelationshipType: Bool {
        switch self {
        case .assignedPullRequest,
                .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .assignedIssue,
                .authoredIssue,
                .commentedIssue:
            return true
        case .readyToMerge,
                .pullRequestMergeConflicts,
                .pullRequestFailedChecks,
                .securityAlert,
                .comment,
                .mention,
                .teamMention,
                .newCommitsAfterComment,
                .newCommitsAfterReview,
                .reviewRequested,
                .teamReviewRequested,
                .reviewApproved,
                .reviewChangesRequested,
                .reviewComment,
                .pullRequestStateChanged,
                .ciActivity,
                .workflowRunning,
                .workflowSucceeded,
                .workflowFailed,
                .workflowApprovalRequired:
            return false
        }
    }

    var isSelfTriggeredRelationshipType: Bool {
        switch self {
        case .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .authoredIssue,
                .commentedIssue:
            return true
        case .assignedPullRequest,
                .assignedIssue,
                .readyToMerge,
                .pullRequestMergeConflicts,
                .pullRequestFailedChecks,
                .securityAlert,
                .comment,
                .mention,
                .teamMention,
                .newCommitsAfterComment,
                .newCommitsAfterReview,
                .reviewRequested,
                .teamReviewRequested,
                .reviewApproved,
                .reviewChangesRequested,
                .reviewComment,
                .pullRequestStateChanged,
                .ciActivity,
                .workflowRunning,
                .workflowSucceeded,
                .workflowFailed,
                .workflowApprovalRequired:
            return false
        }
    }

    var relationshipPriority: Int {
        switch self {
        case .authoredPullRequest, .assignedIssue:
            return 4
        case .assignedPullRequest, .authoredIssue:
            return 3
        case .reviewedPullRequest:
            return 2
        case .commentedPullRequest, .commentedIssue:
            return 1
        default:
            return 0
        }
    }

    var aggregateDisplayPriority: Int {
        switch self {
        case .pullRequestMergeConflicts:
            return 11
        case .pullRequestFailedChecks, .securityAlert:
            return 10
        case .workflowApprovalRequired:
            return 9
        case .workflowFailed:
            return 8
        case .reviewChangesRequested:
            return 7
        case .readyToMerge, .reviewRequested, .teamReviewRequested:
            return 6
        case .reviewApproved:
            return 5
        case .reviewComment, .comment, .mention, .teamMention:
            return 4
        case .newCommitsAfterComment, .newCommitsAfterReview, .pullRequestStateChanged:
            return 3
        case .workflowRunning:
            return 2
        case .workflowSucceeded, .ciActivity:
            return 1
        case .assignedPullRequest,
                .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .assignedIssue,
                .authoredIssue,
                .commentedIssue:
            return 0
        }
    }

    var aggregateUpdateTitle: String {
        switch self {
        case .pullRequestMergeConflicts:
            return "Merge conflicts"
        case .pullRequestFailedChecks:
            return "Checks failed"
        case .workflowRunning:
            return "Workflow running"
        case .workflowSucceeded:
            return "Workflow succeeded"
        case .workflowFailed:
            return "Workflow failed"
        case .workflowApprovalRequired:
            return "Workflow waiting for approval"
        default:
            return accessibilityLabel
        }
    }

    var badgeMeaningLabel: String {
        switch self {
        case .assignedPullRequest, .assignedIssue:
            return "Assigned to you"
        case .authoredPullRequest, .authoredIssue:
            return "Created by you"
        case .reviewedPullRequest:
            return "Reviewed by you"
        case .commentedPullRequest, .commentedIssue:
            return "Commented on by you"
        default:
            return accessibilityLabel
        }
    }

    static func badgeHelpText(
        primary: AttentionItemType,
        secondary: AttentionItemType?
    ) -> String {
        guard let secondary else {
            return primary.badgeMeaningLabel
        }

        return "\(primary.badgeMeaningLabel)\n\(secondary.badgeMeaningLabel)"
    }
}

private struct AttentionSubjectAggregation {
    let subjectItem: AttentionItem
    let relationshipItem: AttentionItem?
}

enum AttentionSubjectViewPolicy {
    static func collapsingUpdates(in items: [AttentionItem]) -> [AttentionItem] {
        let grouped = Dictionary(grouping: items, by: \.subjectKey)
        return grouped.values
            .compactMap(aggregate)
            .sorted { $0.subjectItem.timestamp > $1.subjectItem.timestamp }
            .map(\.subjectItem)
    }

    static func preferredRelationship(in items: [AttentionItem]) -> AttentionItem? {
        aggregate(items)?.relationshipItem
    }

    private static func aggregate(_ items: [AttentionItem]) -> AttentionSubjectAggregation? {
        guard let subjectKey = items.first?.subjectKey else {
            return nil
        }

        let relationshipItem = items
            .filter { $0.type.isRelationshipType }
            .max(by: relationshipSort(lhs:rhs:))

        let updateItems = items.filter { !$0.type.isRelationshipType }
        let primaryItem = updateItems.max(by: updateSort(lhs:rhs:)) ??
            relationshipItem ??
            items.max(by: updateSort(lhs:rhs:))

        guard let primaryItem else {
            return nil
        }

        let titleSource = items.first {
            !$0.type.iconName.contains("bolt") && !$0.title.isEmpty
        } ?? items.max(by: updateSort(lhs:rhs:))

        let title = titleSource?.title ?? subjectLabel(for: subjectKey)
        let repository = items.compactMap(\.repository).first
        let labels = items
            .sorted {
                if $0.labels.count == $1.labels.count {
                    return $0.timestamp > $1.timestamp
                }
                return $0.labels.count > $1.labels.count
            }
            .first?.labels ?? []

        let updates = updateItems
            .sorted(by: { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.type.aggregateDisplayPriority > rhs.type.aggregateDisplayPriority
                }
                return lhs.timestamp > rhs.timestamp
            })
            .reduce(into: [AttentionUpdate]()) { partialResult, item in
                guard partialResult.contains(where: { $0.id == item.updateKey }) == false else {
                    return
                }
                partialResult.append(
                    AttentionUpdate(
                        id: item.updateKey,
                        type: item.type,
                        title: aggregateUpdateTitle(for: item),
                        detail: updateDetail(for: item),
                        timestamp: item.timestamp,
                        actor: item.actor,
                        url: item.url,
                        isTriggeredByCurrentUser: item.isTriggeredByCurrentUser
                    )
                )
            }

        let focusItem = relationshipItem ?? primaryItem
        let subjectURL = AttentionItem.subjectReference(fromSubjectKey: subjectKey)?.webURL ?? primaryItem.url
        let detail = AttentionDetail(
            contextPillTitle: primaryItem.detail.contextPillTitle,
            why: primaryItem.detail.why,
            evidence: primaryItem.detail.evidence,
            updates: updates,
            actions: primaryItem.detail.actions,
            acknowledgement: primaryItem.detail.acknowledgement
        )

        let subjectItem = AttentionItem(
            id: subjectKey,
            subjectKey: subjectKey,
            updateKey: primaryItem.updateKey,
            latestSourceID: primaryItem.latestSourceID,
            stream: stream(for: primaryItem, subjectKey: subjectKey),
            type: primaryItem.type,
            secondaryIndicatorType: secondaryIndicator(
                primaryType: primaryItem.type,
                relationshipItem: relationshipItem
            ),
            focusType: focusItem.type,
            focusActor: focusItem.actor,
            title: title,
            subtitle: primaryItem.subtitle,
            repository: repository,
            labels: labels,
            timestamp: primaryItem.timestamp,
            url: subjectURL,
            actor: primaryItem.actor,
            isTriggeredByCurrentUser: primaryItem.isTriggeredByCurrentUser,
            subjectResolution: primaryItem.subjectResolution ?? items.compactMap(\.subjectResolution).first,
            detail: detail,
            currentUpdateTypes: Set(updateItems.map(\.type)),
            currentRelationshipTypes: Set(items.filter { $0.type.isRelationshipType }.map(\.type)),
            isHistoricalLogEntry: items.allSatisfy(\.isHistoricalLogEntry),
            closureNotificationEligibleOverride: items.contains(where: \.isClosureNotificationEligible),
            postMergeWatchEligibleOverride: items.contains(where: \.isPostMergeWatchEligible),
            isDraft: items.compactMap(\.isDraft).first,
            isUnread: items.contains(where: \.isUnread)
        )

        return AttentionSubjectAggregation(
            subjectItem: subjectItem,
            relationshipItem: relationshipItem
        )
    }

    private static func relationshipSort(lhs: AttentionItem, rhs: AttentionItem) -> Bool {
        if lhs.type.relationshipPriority == rhs.type.relationshipPriority {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.type.relationshipPriority < rhs.type.relationshipPriority
    }

    private static func updateSort(lhs: AttentionItem, rhs: AttentionItem) -> Bool {
        if lhs.type.aggregateDisplayPriority == rhs.type.aggregateDisplayPriority {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.type.aggregateDisplayPriority < rhs.type.aggregateDisplayPriority
    }

    private static func secondaryIndicator(
        primaryType: AttentionItemType,
        relationshipItem: AttentionItem?
    ) -> AttentionItemType? {
        guard let relationshipItem, relationshipItem.type != primaryType else {
            return nil
        }

        return relationshipItem.type
    }

    private static func stream(
        for item: AttentionItem,
        subjectKey: String
    ) -> AttentionStream {
        if let reference = item.subjectReference ?? AttentionItem.subjectReference(fromSubjectKey: subjectKey) {
            switch reference.kind {
            case .pullRequest:
                return .pullRequests
            case .issue:
                return .issues
            }
        }

        return item.stream
    }

    private static func aggregateUpdateTitle(for item: AttentionItem) -> String {
        if item.type == .pullRequestStateChanged,
            let stateTransitionTitle = item.detail.contextPillTitle,
            !stateTransitionTitle.isEmpty {
            return stateTransitionTitle
        }

        return item.type.aggregateUpdateTitle
    }

    private static func updateDetail(for item: AttentionItem) -> String? {
        if item.type == .workflowRunning ||
            item.type == .workflowSucceeded ||
            item.type == .workflowFailed ||
            item.type == .workflowApprovalRequired {
            return item.detail.evidence.first(where: { $0.id == "run" })?.detail ?? item.subtitle
        }

        if let detail = item.detail.why.detail, !detail.isEmpty {
            return detail
        }

        return item.subtitle
    }

    private static func subjectLabel(for subjectKey: String) -> String {
        if let reference = AttentionItem.subjectReference(fromSubjectKey: subjectKey) {
            switch reference.kind {
            case .pullRequest:
                return "Pull Request #\(reference.number)"
            case .issue:
                return "Issue #\(reference.number)"
            }
        }

        return subjectKey
    }
}

struct PullRequestSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let ignoreKey: String
    let number: Int
    let title: String
    let subtitle: String
    let repository: String
    let labels: [GitHubLabel]
    let url: URL
    let updatedAt: Date
    let isDraft: Bool
    let resolution: GitHubSubjectResolution
}

struct TrackedSubjectSummary: Identifiable, Hashable, Sendable {
    let id: String
    let ignoreKey: String
    let type: AttentionItemType
    let number: Int
    let title: String
    let subtitle: String
    let repository: String
    let labels: [GitHubLabel]
    let url: URL
    let updatedAt: Date
    let actor: AttentionActor?
    let isTriggeredByCurrentUser: Bool
    let latestSelfUpdate: TrackedSubjectSelfUpdateSummary?
    let isDraft: Bool
    let resolution: GitHubSubjectResolution
}

struct TrackedSubjectSelfUpdateSummary: Hashable, Sendable {
    let type: AttentionItemType
    let timestamp: Date
    let actor: AttentionActor?
}

struct AuthoredPullRequestSignalSummary: Identifiable, Hashable, Sendable {
    let id: String
    let ignoreKey: String
    let type: AttentionItemType
    let number: Int
    let title: String
    let subtitle: String
    let repository: String
    let labels: [GitHubLabel]
    let url: URL
    let updatedAt: Date
    let actor: AttentionActor?
    let approvalCount: Int?
    let checkSummary: PullRequestCheckSummary
    let isDraft: Bool
}

struct NotificationSummary: Identifiable, Hashable, Sendable {
    let id: String
    let ignoreKey: String
    let type: AttentionItemType
    let title: String
    let subtitle: String
    let repository: String
    let labels: [GitHubLabel]
    let url: URL
    let updatedAt: Date
    let unread: Bool
    let actor: AttentionActor?
    let isTriggeredByCurrentUser: Bool
    let resolution: GitHubSubjectResolution?
    let targetLabel: String?
    let stateTransition: PullRequestStateTransition?
    let detailEvidence: [AttentionEvidence]
}

enum PullRequestStateTransition: String, Hashable, Sendable {
    case merged
    case closed
    case reopened
    case synchronized

    var title: String {
        switch self {
        case .merged:
            return "Merged"
        case .closed:
            return "Closed"
        case .reopened:
            return "Reopened"
        case .synchronized:
            return "Updated"
        }
    }

    var detailLabel: String {
        switch self {
        case .merged:
            return "Pull request merged"
        case .closed:
            return "Pull request closed"
        case .reopened:
            return "Pull request reopened"
        case .synchronized:
            return "Pull request updated"
        }
    }

    var actorVerb: String {
        switch self {
        case .merged:
            return "merged this pull request"
        case .closed:
            return "closed this pull request"
        case .reopened:
            return "reopened this pull request"
        case .synchronized:
            return "updated this pull request"
        }
    }
}

struct ActionRunSummary: Identifiable, Hashable, Sendable {
    let id: String
    let subjectKey: String
    let type: AttentionItemType
    let subjectTitle: String
    let runTitle: String
    let subtitle: String
    let repository: String
    let updatedAt: Date
    let url: URL
    let actor: AttentionActor?
    let isTriggeredByCurrentUser: Bool
    let resolution: GitHubSubjectResolution
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
    let resource: String
    let limit: Int
    let remaining: Int
    let resetAt: Date?
    let pollIntervalHintSeconds: Int?
    let retryAfterSeconds: Int?

    var resourceKey: String {
        let normalized = resource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? "unknown" : normalized
    }

    var resourceDisplayName: String {
        switch resourceKey {
        case "core":
            return "Core"
        case "search":
            return "Search"
        case "graphql":
            return "GraphQL"
        case "code_search":
            return "Code Search"
        case "integration_manifest":
            return "Integration Manifest"
        case "dependency_snapshots":
            return "Dependency Snapshots"
        case "code_scanning_upload":
            return "Code Scanning"
        case "source_import":
            return "Source Import"
        case "unknown":
            return "Unknown"
        default:
            return resourceKey
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    var isExhausted: Bool {
        remaining <= 0
    }

    var isLow: Bool {
        remaining <= max(25, min(100, limit / 50))
    }

    func merged(with other: GitHubRateLimit) -> GitHubRateLimit {
        guard resourceKey == other.resourceKey else {
            return isMoreRestrictive(than: other) ? self : other
        }

        let preferred = isMoreRestrictive(than: other) ? self : other

        return GitHubRateLimit(
            resource: preferred.resource,
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

    static func mostRestrictive(in rateLimits: [GitHubRateLimit]) -> GitHubRateLimit? {
        rateLimits.min { lhs, rhs in
            lhs.isMoreRestrictive(than: rhs)
        }
    }

    static func mergingCollections(
        _ existing: [GitHubRateLimit],
        with incoming: [GitHubRateLimit]
    ) -> [GitHubRateLimit] {
        var mergedByResource = [String: GitHubRateLimit]()

        for sample in existing + incoming {
            let key = sample.resourceKey
            if let current = mergedByResource[key] {
                mergedByResource[key] = current.merged(with: sample)
            } else {
                mergedByResource[key] = sample
            }
        }

        return mergedByResource.values.sorted { lhs, rhs in
            if lhs.isMoreRestrictive(than: rhs) != rhs.isMoreRestrictive(than: lhs) {
                return lhs.isMoreRestrictive(than: rhs)
            }

            return lhs.resourceDisplayName.localizedCaseInsensitiveCompare(rhs.resourceDisplayName)
                == .orderedAscending
        }
    }

    func minimumAutomaticRefreshInterval(
        userConfiguredSeconds: Int,
        now: Date = .now
    ) -> Int {
        var interval = max(userConfiguredSeconds, pollIntervalHintSeconds ?? 0)
        let secondsUntilReset = resetAt.map { Int(ceil($0.timeIntervalSince(now))) }

        if let retryAfterSeconds {
            interval = max(interval, retryAfterSeconds)
        }

        if isExhausted, let secondsUntilReset {
            interval = max(interval, secondsUntilReset)
        } else if limit <= 100 {
            let lowWatermark = max(1, limit / 5)
            if remaining <= lowWatermark, let secondsUntilReset, secondsUntilReset > 0 {
                interval = max(interval, secondsUntilReset)
            }
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

struct GitHubRateLimitSnapshot: Hashable, Sendable {
    let buckets: [GitHubRateLimit]

    var mostRestrictive: GitHubRateLimit? {
        GitHubRateLimit.mostRestrictive(in: buckets)
    }

    var isEmpty: Bool {
        buckets.isEmpty
    }

    func merged(with other: GitHubRateLimitSnapshot) -> GitHubRateLimitSnapshot {
        GitHubRateLimitSnapshot(
            buckets: GitHubRateLimit.mergingCollections(buckets, with: other.buckets)
        )
    }

    static func fromBuckets(_ buckets: [GitHubRateLimit]) -> GitHubRateLimitSnapshot? {
        let merged = GitHubRateLimit.mergingCollections([], with: buckets)
        guard !merged.isEmpty else {
            return nil
        }

        return GitHubRateLimitSnapshot(buckets: merged)
    }
}

struct GitHubSnapshot: Sendable {
    let login: String
    let attentionItems: [AttentionItem]
    let rateLimits: GitHubRateLimitSnapshot?
    let notificationScanState: NotificationScanState
    let teamMembershipCache: TeamMembershipCache
}

struct PullRequestDashboardFetchResult: Sendable {
    let login: String
    let dashboard: PullRequestDashboard
    let rateLimits: GitHubRateLimitSnapshot?
    let teamMembershipCache: TeamMembershipCache
}

struct IssueDashboardFetchResult: Sendable {
    let login: String
    let dashboard: IssueDashboard
    let rateLimits: GitHubRateLimitSnapshot?
}

struct NotificationScanState: Codable, Hashable, Sendable {
    let knownActionableThreadIDs: [String]
    let preferredPageDepth: Int

    static let `default` = NotificationScanState(
        knownActionableThreadIDs: [],
        preferredPageDepth: 2
    )

    var normalized: NotificationScanState {
        NotificationScanState(
            knownActionableThreadIDs: Array(NSOrderedSet(array: knownActionableThreadIDs))
                .compactMap { $0 as? String }
                .prefix(128)
                .map { $0 },
            preferredPageDepth: min(max(preferredPageDepth, 2), 10)
        )
    }
}

struct TeamMembershipCache: Codable, Hashable, Sendable {
    let membershipKeys: [String]
    let fetchedAt: Date?
    let lastAttemptAt: Date?

    static let `default` = TeamMembershipCache(
        membershipKeys: [],
        fetchedAt: nil,
        lastAttemptAt: nil
    )

    var normalized: TeamMembershipCache {
        let normalizedKeys = membershipKeys.map { $0.lowercased() }
        return TeamMembershipCache(
            membershipKeys: Array(NSOrderedSet(array: normalizedKeys))
                .compactMap { $0 as? String }
                .prefix(512)
                .map { $0 },
            fetchedAt: fetchedAt,
            lastAttemptAt: lastAttemptAt
        )
    }

    func contains(owner: String, slug: String) -> Bool {
        normalized.membershipKeys.contains(Self.membershipKey(owner: owner, slug: slug))
    }

    func refreshed(membershipKeys: [String], at date: Date = .now) -> TeamMembershipCache {
        TeamMembershipCache(
            membershipKeys: membershipKeys,
            fetchedAt: date,
            lastAttemptAt: date
        ).normalized
    }

    func recordingAttempt(at date: Date = .now) -> TeamMembershipCache {
        TeamMembershipCache(
            membershipKeys: membershipKeys,
            fetchedAt: fetchedAt,
            lastAttemptAt: date
        ).normalized
    }

    func isFresh(relativeTo referenceDate: Date = .now) -> Bool {
        guard let lastAttemptAt else {
            return false
        }

        return referenceDate.timeIntervalSince(lastAttemptAt) < 86_400
    }

    static func membershipKey(owner: String, slug: String) -> String {
        "\(owner.lowercased())/\(slug.lowercased())"
    }
}

struct AcknowledgedWorkflowState: Codable, Hashable, Sendable {
    let subjectKey: String
    let acknowledgedRunIDs: Set<String>
    let acknowledgedAt: Date

    func coversRunID(_ runID: String) -> Bool {
        acknowledgedRunIDs.contains(runID)
    }

    func adding(runID: String) -> AcknowledgedWorkflowState {
        AcknowledgedWorkflowState(
            subjectKey: subjectKey,
            acknowledgedRunIDs: acknowledgedRunIDs.union([runID]),
            acknowledgedAt: Date()
        )
    }
}

enum AttentionSnoozePreset: String, CaseIterable, Identifiable, Hashable, Sendable {
    case oneHour
    case tomorrowMorning
    case oneWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour:
            return "For 1 Hour"
        case .tomorrowMorning:
            return "Until Tomorrow Morning"
        case .oneWeek:
            return "For 1 Week"
        }
    }

    func snoozedUntil(
        from referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        switch self {
        case .oneHour:
            return referenceDate.addingTimeInterval(60 * 60)
        case .tomorrowMorning:
            let startOfToday = calendar.startOfDay(for: referenceDate)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? referenceDate
            return calendar.date(byAdding: .hour, value: 9, to: tomorrow) ?? tomorrow
        case .oneWeek:
            return calendar.date(byAdding: .day, value: 7, to: referenceDate)
                ?? referenceDate.addingTimeInterval(7 * 24 * 60 * 60)
        }
    }
}

private struct AttentionSubjectPlaceholder {
    let ignoreKey: String
    let title: String
    let subtitle: String
    let url: URL
}

private enum AttentionSubjectPlaceholderFactory {
    static func make(
        for ignoreKey: String,
        fallbackTitle: String
    ) -> AttentionSubjectPlaceholder {
        if let url = URL(string: ignoreKey),
            let parsed = make(fromCanonicalURL: url) {
            return parsed
        }

        if ignoreKey.hasPrefix("issue:") {
            let value = String(ignoreKey.dropFirst(6))
            let components = value.split(separator: "#", maxSplits: 1).map(String.init)
            if components.count == 2 {
                let url = URL(string: "https://github.com/\(components[0])/issues/\(components[1])")!
                return AttentionSubjectPlaceholder(
                    ignoreKey: url.absoluteString,
                    title: "Issue #\(components[1])",
                    subtitle: components[0],
                    url: url
                )
            }
        }

        if ignoreKey.hasPrefix("pr:") {
            let value = String(ignoreKey.dropFirst(3))
            let components = value.split(separator: "#", maxSplits: 1).map(String.init)
            if components.count == 2 {
                let url = URL(string: "https://github.com/\(components[0])/pull/\(components[1])")!
                return AttentionSubjectPlaceholder(
                    ignoreKey: url.absoluteString,
                    title: "Pull Request #\(components[1])",
                    subtitle: components[0],
                    url: url
                )
            }
        }

        if ignoreKey.hasPrefix("url:"),
            let url = URL(string: String(ignoreKey.dropFirst(4))),
            let parsed = make(fromCanonicalURL: url) {
            return parsed
        }

        if let url = URL(string: ignoreKey) {
            return AttentionSubjectPlaceholder(
                ignoreKey: url.absoluteString,
                title: fallbackTitle,
                subtitle: url.host ?? "GitHub",
                url: url
            )
        }

        return AttentionSubjectPlaceholder(
            ignoreKey: ignoreKey,
            title: fallbackTitle,
            subtitle: "GitHub",
            url: URL(string: "https://github.com")!
        )
    }

    private static func make(fromCanonicalURL url: URL) -> AttentionSubjectPlaceholder? {
        let components = url.pathComponents

        if let pullIndex = components.firstIndex(of: "pull"),
            pullIndex >= 2,
            pullIndex + 1 < components.count {
            let repository = "\(components[pullIndex - 2])/\(components[pullIndex - 1])"
            let number = components[pullIndex + 1]
            return AttentionSubjectPlaceholder(
                ignoreKey: url.absoluteString,
                title: "Pull Request #\(number)",
                subtitle: repository,
                url: url
            )
        }

        if let issueIndex = components.firstIndex(of: "issues"),
            issueIndex >= 2,
            issueIndex + 1 < components.count {
            let repository = "\(components[issueIndex - 2])/\(components[issueIndex - 1])"
            let number = components[issueIndex + 1]
            return AttentionSubjectPlaceholder(
                ignoreKey: url.absoluteString,
                title: "Issue #\(number)",
                subtitle: repository,
                url: url
            )
        }

        return nil
    }
}

struct IgnoredAttentionSubject: Identifiable, Hashable, Codable, Sendable {
    let ignoreKey: String
    let title: String
    let subtitle: String
    let url: URL
    let ignoredAt: Date

    var id: String { ignoreKey }

    static func placeholder(for ignoreKey: String, ignoredAt: Date = .now) -> IgnoredAttentionSubject {
        let placeholder = AttentionSubjectPlaceholderFactory.make(
            for: ignoreKey,
            fallbackTitle: "Ignored Item"
        )
        return IgnoredAttentionSubject(
            ignoreKey: placeholder.ignoreKey,
            title: placeholder.title,
            subtitle: placeholder.subtitle,
            url: placeholder.url,
            ignoredAt: ignoredAt
        )
    }
}

struct SnoozedAttentionSubject: Identifiable, Hashable, Codable, Sendable {
    let ignoreKey: String
    let title: String
    let subtitle: String
    let url: URL
    let snoozedAt: Date
    let snoozedUntil: Date

    var id: String { ignoreKey }

    var isActive: Bool {
        snoozedUntil > Date()
    }

    static func placeholder(
        for ignoreKey: String,
        snoozedAt: Date = .now,
        snoozedUntil: Date
    ) -> SnoozedAttentionSubject {
        let placeholder = AttentionSubjectPlaceholderFactory.make(
            for: ignoreKey,
            fallbackTitle: "Snoozed Item"
        )
        return SnoozedAttentionSubject(
            ignoreKey: placeholder.ignoreKey,
            title: placeholder.title,
            subtitle: placeholder.subtitle,
            url: placeholder.url,
            snoozedAt: snoozedAt,
            snoozedUntil: snoozedUntil
        )
    }
}

struct IgnoreUndoState: Identifiable, Hashable, Sendable {
    let subjects: [IgnoredAttentionSubject]
    let expiresAt: Date

    var id: String {
        subjects.map(\.ignoreKey).sorted().joined(separator: "|")
    }

    var primarySubject: IgnoredAttentionSubject? {
        subjects.first
    }
}

struct SnoozeUndoState: Identifiable, Hashable, Sendable {
    let subjects: [SnoozedAttentionSubject]
    let expiresAt: Date

    var id: String {
        let subjectID = subjects.map(\.ignoreKey).sorted().joined(separator: "|")
        let wakeID = subjects.map(\.snoozedUntil.timeIntervalSince1970).max() ?? 0
        return "\(subjectID)#\(wakeID)"
    }

    var primarySubject: SnoozedAttentionSubject? {
        subjects.first
    }
}

enum InboxRuleItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case pullRequest
    case issue
    case workflow

    var title: String {
        switch self {
        case .pullRequest:
            return "Pull Request"
        case .issue:
            return "Issue"
        case .workflow:
            return "Workflow"
        }
    }

    var pluralTitle: String {
        switch self {
        case .pullRequest:
            return "Pull requests"
        case .issue:
            return "Issues"
        case .workflow:
            return "Workflows"
        }
    }

    var iconName: String {
        switch self {
        case .pullRequest: return "arrow.triangle.pull"
        case .issue: return "exclamationmark.circle"
        case .workflow: return "bolt.horizontal.circle"
        }
    }

    var defaultRuleName: String {
        "\(title) Rule"
    }

    var availableConditionKinds: [InboxRuleConditionKind] {
        switch self {
        case .pullRequest:
            return [.relationship, .signal, .viewerReview]
        case .issue:
            return [.relationship]
        case .workflow:
            return [.relationship, .signal]
        }
    }

    var availableRelationships: [InboxRuleRelationship] {
        switch self {
        case .pullRequest:
            return [.authored, .assigned, .reviewed, .commented, .interacted]
        case .issue:
            return [.authored, .assigned, .commented, .interacted]
        case .workflow:
            return [.authored, .assigned, .reviewed, .commented, .interacted]
        }
    }

    var availableSignals: [InboxRuleSignal] {
        switch self {
        case .pullRequest:
            return [.readyToMerge, .readyForReview, .mergeConflicts, .failedChecks]
        case .issue:
            return []
        case .workflow:
            return [.workflowFailed, .workflowApprovalRequired, .workflowRunning]
        }
    }
}

enum InboxRuleMatchMode: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case any

    var title: String {
        switch self {
        case .all:
            return "All Conditions"
        case .any:
            return "Any Condition"
        }
    }

}

enum InboxRuleConditionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case relationship
    case signal
    case viewerReview

    var title: String {
        switch self {
        case .relationship:
            return "Relationship"
        case .signal:
            return "Signal"
        case .viewerReview:
            return "Viewer Review"
        }
    }
}

enum InboxRuleRelationship: String, Codable, CaseIterable, Hashable, Sendable {
    case authored
    case assigned
    case reviewed
    case commented
    case interacted

    var title: String {
        title(for: nil)
    }

    func title(for itemKind: InboxRuleItemKind?) -> String {
        switch (self, itemKind) {
        case (.authored, .workflow):
            return "From PRs you authored"
        case (.authored, .issue):
            return "Created by you"
        case (.authored, _):
            return "Authored by you"
        case (.assigned, .workflow):
            return "From PRs assigned to you"
        case (.assigned, _):
            return "Assigned to you"
        case (.reviewed, .workflow):
            return "From PRs you reviewed"
        case (.reviewed, _):
            return "Reviewed by you"
        case (.commented, .workflow):
            return "From PRs you commented on"
        case (.commented, _):
            return "Commented on by you"
        case (.interacted, .workflow):
            return "From PRs you interacted with"
        case (.interacted, _):
            return "You interacted with"
        }
    }

    var expandedRelationships: Set<InboxRuleRelationship> {
        switch self {
        case .interacted:
            return [.reviewed, .commented]
        default:
            return [self]
        }
    }
}

enum InboxRuleSignal: String, Codable, CaseIterable, Hashable, Sendable {
    case readyToMerge
    case readyForReview
    case mergeConflicts
    case failedChecks
    case workflowFailed
    case workflowApprovalRequired
    case workflowRunning

    var title: String {
        switch self {
        case .readyToMerge:
            return "Ready to Merge"
        case .readyForReview:
            return "Ready for Review"
        case .mergeConflicts:
            return "Merge Conflicts"
        case .failedChecks:
            return "Failed Checks"
        case .workflowFailed:
            return "Workflow Failed"
        case .workflowApprovalRequired:
            return "Workflow Awaiting Approval"
        case .workflowRunning:
            return "Workflow Queued or Running"
        }
    }
}

enum InboxRuleReviewCondition: String, Codable, CaseIterable, Hashable, Sendable {
    case missing
    case present

    var title: String {
        switch self {
        case .missing:
            return "No Review from You"
        case .present:
            return "Has Review from You"
        }
    }
}

struct InboxRuleCondition: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: InboxRuleConditionKind
    var isNegated: Bool
    var relationshipValues: Set<InboxRuleRelationship>
    var signalValues: Set<InboxRuleSignal>
    var viewerReviewValue: InboxRuleReviewCondition

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case isNegated
        case relationshipValues
        case signalValues
        case viewerReviewValue
    }

    init(
        id: UUID,
        kind: InboxRuleConditionKind,
        isNegated: Bool,
        relationshipValues: Set<InboxRuleRelationship>,
        signalValues: Set<InboxRuleSignal>,
        viewerReviewValue: InboxRuleReviewCondition
    ) {
        self.id = id
        self.kind = kind
        self.isNegated = isNegated
        self.relationshipValues = relationshipValues
        self.signalValues = signalValues
        self.viewerReviewValue = viewerReviewValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(InboxRuleConditionKind.self, forKey: .kind)
        isNegated = try container.decodeIfPresent(Bool.self, forKey: .isNegated) ?? false
        relationshipValues = try container.decodeIfPresent(
            Set<InboxRuleRelationship>.self,
            forKey: .relationshipValues
        ) ?? []
        signalValues = try container.decodeIfPresent(
            Set<InboxRuleSignal>.self,
            forKey: .signalValues
        ) ?? []
        viewerReviewValue = try container.decodeIfPresent(
            InboxRuleReviewCondition.self,
            forKey: .viewerReviewValue
        ) ?? .missing
    }

    static func relationship(
        _ values: Set<InboxRuleRelationship>,
        isNegated: Bool = false,
        id: UUID = UUID()
    ) -> InboxRuleCondition {
        InboxRuleCondition(
            id: id,
            kind: .relationship,
            isNegated: isNegated,
            relationshipValues: values,
            signalValues: [],
            viewerReviewValue: .missing
        )
    }

    static func signal(
        _ values: Set<InboxRuleSignal>,
        isNegated: Bool = false,
        id: UUID = UUID()
    ) -> InboxRuleCondition {
        InboxRuleCondition(
            id: id,
            kind: .signal,
            isNegated: isNegated,
            relationshipValues: [],
            signalValues: values,
            viewerReviewValue: .missing
        )
    }

    static func viewerReview(
        _ value: InboxRuleReviewCondition,
        isNegated: Bool = false,
        id: UUID = UUID()
    ) -> InboxRuleCondition {
        InboxRuleCondition(
            id: id,
            kind: .viewerReview,
            isNegated: isNegated,
            relationshipValues: [],
            signalValues: [],
            viewerReviewValue: value
        )
    }

    static func `default`(
        for kind: InboxRuleConditionKind,
        itemKind: InboxRuleItemKind,
        id: UUID = UUID()
    ) -> InboxRuleCondition {
        switch kind {
        case .relationship:
            let value = itemKind.availableRelationships.first ?? .authored
            return .relationship([value], id: id)
        case .signal:
            let value = itemKind.availableSignals.first ?? .readyToMerge
            return .signal([value], id: id)
        case .viewerReview:
            return .viewerReview(.missing, id: id)
        }
    }

    func normalized(for itemKind: InboxRuleItemKind) -> InboxRuleCondition? {
        switch kind {
        case .relationship:
            let filtered = relationshipValues.intersection(itemKind.availableRelationships)
            guard !filtered.isEmpty else {
                return nil
            }

            var copy = self
            copy.relationshipValues = filtered
            copy.signalValues = []
            return copy
        case .signal:
            let filtered = signalValues.intersection(itemKind.availableSignals)
            guard !filtered.isEmpty else {
                return nil
            }

            var copy = self
            copy.relationshipValues = []
            copy.signalValues = filtered
            return copy
        case .viewerReview:
            guard itemKind == .pullRequest else {
                return nil
            }

            var copy = self
            copy.relationshipValues = []
            copy.signalValues = []
            return copy
        }
    }

    var summary: String {
        summaryPhrase(for: nil)
    }

    func summaryPhrase(for itemKind: InboxRuleItemKind?) -> String {
        switch kind {
        case .relationship:
            let phrases = relationshipValues
                .sorted { $0.title < $1.title }
                .map {
                    relationshipPhrase(
                        for: $0,
                        itemKind: itemKind,
                        isNegated: isNegated
                    )
                }
            return Self.joinedPhrases(phrases, separator: " or ")
        case .signal:
            let phrases = signalValues
                .sorted { $0.title < $1.title }
                .map {
                    signalPhrase(
                        for: $0,
                        itemKind: itemKind,
                        isNegated: isNegated
                    )
                }
            return Self.joinedPhrases(phrases, separator: " or ")
        case .viewerReview:
            switch (viewerReviewValue, isNegated) {
            case (.missing, false), (.present, true):
                return "without your review"
            case (.present, false), (.missing, true):
                return "with your review"
            }
        }
    }

    private func relationshipPhrase(
        for relationship: InboxRuleRelationship,
        itemKind: InboxRuleItemKind?,
        isNegated: Bool
    ) -> String {
        let label = relationship.title(for: itemKind).lowercased()
        return isNegated ? "not \(label)" : label
    }

    private func signalPhrase(
        for signal: InboxRuleSignal,
        itemKind: InboxRuleItemKind?,
        isNegated: Bool
    ) -> String {
        switch signal {
        case .readyToMerge:
            return isNegated ? "not ready to merge" : "ready to merge"
        case .readyForReview:
            return isNegated ? "still in draft" : "ready for review"
        case .mergeConflicts:
            return isNegated ? "without merge conflicts" : "with merge conflicts"
        case .failedChecks:
            return isNegated ? "without failed checks" : "with failed checks"
        case .workflowFailed:
            return isNegated ? "without failed runs" : "with failed runs"
        case .workflowApprovalRequired:
            return isNegated ? "not awaiting approval" : "awaiting approval"
        case .workflowRunning:
            return isNegated ? "not queued or running" : "queued or running"
        }
    }

    private static func joinedPhrases(
        _ phrases: [String],
        separator: String
    ) -> String {
        phrases.filter { !$0.isEmpty }.joined(separator: separator)
    }
}

struct InboxSectionRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var itemKind: InboxRuleItemKind
    var matchMode: InboxRuleMatchMode
    var conditions: [InboxRuleCondition]
    var isEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case itemKind
        case matchMode
        case conditions
        case isEnabled
    }

    init(
        id: UUID = UUID(),
        name: String,
        itemKind: InboxRuleItemKind,
        matchMode: InboxRuleMatchMode = .all,
        conditions: [InboxRuleCondition],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.itemKind = itemKind
        self.matchMode = matchMode
        self.conditions = conditions
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        itemKind = try container.decode(InboxRuleItemKind.self, forKey: .itemKind)
        matchMode = try container.decode(InboxRuleMatchMode.self, forKey: .matchMode)
        conditions = try container.decode([InboxRuleCondition].self, forKey: .conditions)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }

    static func newCustom(itemKind: InboxRuleItemKind = .pullRequest) -> InboxSectionRule {
        InboxSectionRule(
            name: "New Rule",
            itemKind: itemKind,
            conditions: [
                .default(for: .relationship, itemKind: itemKind)
            ]
        )
    }

    var normalized: InboxSectionRule {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return InboxSectionRule(
            id: id,
            name: trimmedName.isEmpty ? itemKind.defaultRuleName : trimmedName,
            itemKind: itemKind,
            matchMode: .all,
            conditions: conditions.compactMap { $0.normalized(for: itemKind) },
            isEnabled: isEnabled
        )
    }

    var summary: String {
        let normalizedRule = normalized
        guard !normalizedRule.conditions.isEmpty else {
            return "All \(normalizedRule.itemKind.pluralTitle.lowercased())"
        }

        let details = normalizedRule.conditions.map {
            $0.summaryPhrase(for: normalizedRule.itemKind)
        }.filter { !$0.isEmpty }

        guard !details.isEmpty else {
            return "All \(normalizedRule.itemKind.pluralTitle.lowercased())"
        }

        return "\(normalizedRule.itemKind.pluralTitle) · \(details.joined(separator: " · "))"
    }

    private static func joinedSummaryDetails(_ details: [String]) -> String {
        switch details.count {
        case 0:
            return ""
        case 1:
            return details[0]
        case 2:
            return "\(details[0]) and \(details[1])"
        default:
            let prefix = details.dropLast().joined(separator: ", ")
            return "\(prefix), and \(details.last!)"
        }
    }
}

struct LegacyInboxSectionConfiguration: Codable, Hashable, Sendable {
    var enabledRules: Set<DefaultInboxRule>
}

struct InboxRuleFacts: Hashable, Sendable {
    let itemKinds: Set<InboxRuleItemKind>
    let relationships: Set<InboxRuleRelationship>
    let signals: Set<InboxRuleSignal>
    let hasViewerReview: Bool
}

enum DefaultInboxRule: String, Codable, CaseIterable, Hashable, Sendable {
    case authoredReadyToMerge
    case authoredDraftPullRequests
    case authoredMergeConflicts
    case authoredFailedChecks
    case assignedPullRequestsWithoutReview
    case authoredWorkflowFailed
    case interactedWorkflowFailed
    case relatedWorkflowApprovalRequired
    case assignedIssues

    var title: String {
        switch self {
        case .authoredReadyToMerge:
            return "Your approved PRs ready to merge"
        case .authoredDraftPullRequests:
            return "Your draft PRs"
        case .authoredMergeConflicts:
            return "Your PRs with merge conflicts"
        case .authoredFailedChecks:
            return "Your PRs with failed checks"
        case .assignedPullRequestsWithoutReview:
            return "Open PRs assigned to you"
        case .authoredWorkflowFailed:
            return "Failed workflows on your PRs"
        case .interactedWorkflowFailed:
            return "Failed workflows on PRs you interacted with"
        case .relatedWorkflowApprovalRequired:
            return "Workflows awaiting approval on your PRs"
        case .assignedIssues:
            return "Open issues assigned to you"
        }
    }

    var subtitle: String {
        switch self {
        case .authoredReadyToMerge:
            return "Open pull requests you authored that are approved, checks passed, and are ready to merge."
        case .authoredDraftPullRequests:
            return "Open pull requests you authored that are still in draft."
        case .authoredMergeConflicts:
            return "Open pull requests you authored that need conflict resolution."
        case .authoredFailedChecks:
            return "Open pull requests you authored that currently have failing checks."
        case .assignedPullRequestsWithoutReview:
            return "Open pull requests assigned to you."
        case .authoredWorkflowFailed:
            return "Failed workflows tied to pull requests you authored."
        case .interactedWorkflowFailed:
            return "Failed workflows on pull requests you reviewed or commented on."
        case .relatedWorkflowApprovalRequired:
            return "Workflow runs waiting for approval on pull requests you authored, reviewed, or are assigned to."
        case .assignedIssues:
            return "Open issues that are assigned to you."
        }
    }

    fileprivate var stableID: UUID {
        switch self {
        case .authoredReadyToMerge:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4501")!
        case .authoredDraftPullRequests:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4509")!
        case .authoredMergeConflicts:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4502")!
        case .authoredFailedChecks:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4503")!
        case .assignedPullRequestsWithoutReview:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4504")!
        case .authoredWorkflowFailed:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4508")!
        case .interactedWorkflowFailed:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4505")!
        case .relatedWorkflowApprovalRequired:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4506")!
        case .assignedIssues:
            return UUID(uuidString: "F73752E8-2A4B-4C36-82AA-9A9A2A6C4507")!
        }
    }

    fileprivate var defaultDefinition: InboxSectionRule {
        switch self {
        case .authoredReadyToMerge:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .pullRequest,
                matchMode: .all,
                conditions: [
                    .relationship([.authored]),
                    .signal([.readyToMerge])
                ],
                isEnabled: true
            )
        case .authoredDraftPullRequests:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .pullRequest,
                matchMode: .all,
                conditions: [
                    .relationship([.authored]),
                    .signal([.readyForReview], isNegated: true)
                ],
                isEnabled: true
            )
        case .authoredMergeConflicts:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .pullRequest,
                matchMode: .all,
                conditions: [
                    .relationship([.authored]),
                    .signal([.mergeConflicts])
                ],
                isEnabled: true
            )
        case .authoredFailedChecks:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .pullRequest,
                matchMode: .all,
                conditions: [
                    .relationship([.authored]),
                    .signal([.failedChecks])
                ],
                isEnabled: true
            )
        case .assignedPullRequestsWithoutReview:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .pullRequest,
                matchMode: .all,
                conditions: [
                    .relationship([.assigned])
                ],
                isEnabled: true
            )
        case .authoredWorkflowFailed:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .workflow,
                matchMode: .all,
                conditions: [
                    .relationship([.authored]),
                    .signal([.workflowFailed])
                ],
                isEnabled: true
            )
        case .interactedWorkflowFailed:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .workflow,
                matchMode: .all,
                conditions: [
                    .relationship([.interacted]),
                    .signal([.workflowFailed])
                ],
                isEnabled: true
            )
        case .relatedWorkflowApprovalRequired:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .workflow,
                matchMode: .all,
                conditions: [
                    .relationship([.authored]),
                    .signal([.workflowApprovalRequired])
                ],
                isEnabled: true
            )
        case .assignedIssues:
            return InboxSectionRule(
                id: stableID,
                name: title,
                itemKind: .issue,
                matchMode: .all,
                conditions: [
                    .relationship([.assigned])
                ],
                isEnabled: true
            )
        }
    }
}

struct InboxSection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var rules: [InboxSectionRule]
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, rules: [InboxSectionRule], isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.rules = rules
        self.isEnabled = isEnabled
    }

    var enabledRules: [InboxSectionRule] {
        isEnabled ? rules.filter(\.isEnabled) : []
    }

    var ruleCount: Int { rules.count }
    var enabledRuleCount: Int { rules.filter(\.isEnabled).count }
}

struct InboxSectionConfiguration: Codable, Hashable, Sendable {
    var sections: [InboxSection]

    private static let defaultSectionID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    private static let radarSectionID = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!

    static let `default`: InboxSectionConfiguration = {
        let defaultRules: [DefaultInboxRule] = [
            .authoredReadyToMerge,
            .authoredMergeConflicts,
            .authoredFailedChecks,
            .assignedPullRequestsWithoutReview,
            .assignedIssues,
            .relatedWorkflowApprovalRequired,
            .authoredWorkflowFailed
        ]
        let radarRules: [DefaultInboxRule] = [
            .interactedWorkflowFailed
        ]
        return InboxSectionConfiguration(sections: [
            InboxSection(
                id: defaultSectionID,
                name: "Your Turn",
                rules: defaultRules.map(\.defaultDefinition)
            ),
            InboxSection(
                id: radarSectionID,
                name: "On Your Radar",
                rules: radarRules.map(\.defaultDefinition)
            )
        ])
    }()

    /// Backward-compatible computed property: flattens all rules across sections.
    var rules: [InboxSectionRule] {
        sections.flatMap(\.rules)
    }

    var enabledRules: [InboxSectionRule] {
        sections.flatMap(\.enabledRules).map(\.normalized)
    }

    var normalized: InboxSectionConfiguration {
        InboxSectionConfiguration(
            sections: sections.map { section in
                InboxSection(
                    id: section.id,
                    name: section.name,
                    rules: section.rules.map(\.normalized),
                    isEnabled: section.isEnabled
                )
            }
        )
    }

    /// Convenience initializer that wraps a flat rule array into a single "Your Turn" section.
    init(rules: [InboxSectionRule]) {
        self.sections = [
            InboxSection(name: "Your Turn", rules: rules)
        ]
    }

    init(sections: [InboxSection]) {
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case sections
        case rules
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sections, forKey: .sections)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let sections = try? container.decode([InboxSection].self, forKey: .sections) {
            self.sections = sections
        } else if let flatRules = try? container.decode([InboxSectionRule].self, forKey: .rules) {
            // Legacy format: flat rules array, possibly with "section" strings baked in.
            // Group by the old section value if present in the JSON (we parse it manually).
            // Since the new InboxSectionRule no longer has a section property,
            // decode the raw JSON to extract section names.
            struct LegacyRuleWithSection: Decodable {
                let section: String?
            }

            var sectionOrder = [String]()
            var grouped = [String: [InboxSectionRule]]()
            let legacySections: [LegacyRuleWithSection]
            if let legacy = try? container.decode([LegacyRuleWithSection].self, forKey: .rules) {
                legacySections = legacy
            } else {
                legacySections = flatRules.map { _ in LegacyRuleWithSection(section: nil) }
            }

            for (rule, legacy) in zip(flatRules, legacySections) {
                let sectionName = legacy.section ?? "Your Turn"
                if !sectionOrder.contains(sectionName) {
                    sectionOrder.append(sectionName)
                }
                grouped[sectionName, default: []].append(rule)
            }

            self.sections = sectionOrder.map { name in
                InboxSection(name: name, rules: grouped[name] ?? [])
            }
        } else {
            self.sections = []
        }
    }

    static func migrated(from legacy: LegacyInboxSectionConfiguration) -> InboxSectionConfiguration {
        InboxSectionConfiguration(
            rules: DefaultInboxRule.allCases.map { rule in
                var definition = rule.defaultDefinition
                definition.isEnabled = legacy.enabledRules.contains(rule)
                return definition
            }
        ).normalized
    }

    func migratingV2ToV3() -> InboxSectionConfiguration {
        let newRule = DefaultInboxRule.authoredDraftPullRequests.defaultDefinition
        guard !rules.contains(where: { $0.id == newRule.id }) else {
            return normalized
        }

        let sectionIndex = sections.firstIndex(where: { $0.id == Self.defaultSectionID })
            ?? sections.firstIndex(where: { $0.name == "Your Turn" })
            ?? sections.indices.first
        guard let sectionIndex else {
            return normalized
        }

        var updatedSections = sections
        updatedSections[sectionIndex].rules.append(newRule)
        return InboxSectionConfiguration(sections: updatedSections).normalized
    }

    // MARK: - Rule CRUD

    func replacing(_ rule: InboxSectionRule) -> InboxSectionConfiguration {
        var updatedSections = sections
        for i in updatedSections.indices {
            if let j = updatedSections[i].rules.firstIndex(where: { $0.id == rule.id }) {
                updatedSections[i].rules[j] = rule
                return InboxSectionConfiguration(sections: updatedSections).normalized
            }
        }
        // Rule not found in any section — append to first section if available.
        if !updatedSections.isEmpty {
            updatedSections[0].rules.append(rule)
        }
        return InboxSectionConfiguration(sections: updatedSections).normalized
    }

    func removingRule(id: UUID) -> InboxSectionConfiguration {
        var updatedSections = sections
        for i in updatedSections.indices {
            updatedSections[i].rules.removeAll { $0.id == id }
        }
        return InboxSectionConfiguration(sections: updatedSections).normalized
    }

    func addingRule(_ rule: InboxSectionRule, toSectionID sectionID: UUID) -> InboxSectionConfiguration {
        var updatedSections = sections
        if let i = updatedSections.firstIndex(where: { $0.id == sectionID }) {
            updatedSections[i].rules.append(rule)
        }
        return InboxSectionConfiguration(sections: updatedSections).normalized
    }

    func duplicatingRule(id: UUID) -> InboxSectionConfiguration {
        var updatedSections = sections
        for i in updatedSections.indices {
            if let j = updatedSections[i].rules.firstIndex(where: { $0.id == id }) {
                var dup = updatedSections[i].rules[j]
                dup.id = UUID()
                updatedSections[i].rules.insert(dup, at: j + 1)
                return InboxSectionConfiguration(sections: updatedSections).normalized
            }
        }
        return self
    }

    // MARK: - Section CRUD

    func replacing(_ section: InboxSection) -> InboxSectionConfiguration {
        var updatedSections = sections
        if let i = updatedSections.firstIndex(where: { $0.id == section.id }) {
            updatedSections[i] = section
        }
        return InboxSectionConfiguration(sections: updatedSections)
    }

    func addingSection(_ section: InboxSection) -> InboxSectionConfiguration {
        InboxSectionConfiguration(sections: sections + [section])
    }

    func removingSection(id: UUID) -> InboxSectionConfiguration {
        InboxSectionConfiguration(sections: sections.filter { $0.id != id })
    }

    func movingSection(id: UUID, direction: Int) -> InboxSectionConfiguration {
        var updatedSections = sections
        guard let index = updatedSections.firstIndex(where: { $0.id == id }) else {
            return self
        }
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < updatedSections.count else {
            return self
        }
        updatedSections.swapAt(index, newIndex)
        return InboxSectionConfiguration(sections: updatedSections)
    }
}

enum AttentionItemVisibilityPolicy {
    static func excludingIgnoredSubjects(
        _ items: [AttentionItem],
        ignoredKeys: Set<String>
    ) -> [AttentionItem] {
        items.filter { !ignoredKeys.contains($0.ignoreKey) }
    }

    static func excludingSnoozedSubjects(
        _ items: [AttentionItem],
        snoozedKeys: Set<String>
    ) -> [AttentionItem] {
        items.filter { !snoozedKeys.contains($0.ignoreKey) }
    }

    static func excludingHistoricalLogEntries(
        _ items: [AttentionItem]
    ) -> [AttentionItem] {
        items.filter { !$0.isHistoricalLogEntry }
    }
}

enum AttentionUnreadSessionPolicy {
    static func updatingCachedSubjectKeys(
        _ cachedSubjectKeys: Set<String>,
        with items: [AttentionItem]
    ) -> Set<String> {
        let currentSubjectKeys = Set(items.map(\.subjectKey))
        let currentUnreadKeys = Set(items.filter(\.isUnread).map(\.subjectKey))
        return cachedSubjectKeys
            .intersection(currentSubjectKeys)
            .union(currentUnreadKeys)
    }

    static func filteringVisibleItems(
        _ items: [AttentionItem],
        isUnreadFilterActive: Bool,
        cachedSubjectKeys: Set<String>
    ) -> [AttentionItem] {
        guard isUnreadFilterActive else {
            return items
        }

        return items.filter { item in
            item.isUnread || cachedSubjectKeys.contains(item.subjectKey)
        }
    }
}

enum AttentionItemSearchPolicy {
    static func matching(_ items: [AttentionItem], query: String) -> [AttentionItem] {
        let searchTerms = queryTerms(from: query)
        guard !searchTerms.isEmpty else {
            return items
        }

        return items.filter { item in
            let searchableFields = searchableFields(for: item)
            return searchTerms.allSatisfy { term in
                searchableFields.contains { field in
                    field.localizedStandardContains(term)
                }
            }
        }
    }

    private static func queryTerms(from query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func searchableFields(for item: AttentionItem) -> [String] {
        var fields = [
            item.title,
            item.subtitle,
            item.type.nativeNotificationTitle,
            item.stream.title
        ]

        if let repository = item.repository {
            fields.append(repository)
        }

        if let actorLogin = item.actor?.login {
            fields.append(actorLogin)
        }

        if let focusActorLogin = item.focusActor?.login {
            fields.append(focusActorLogin)
        }

        fields.append(contentsOf: item.labels.map(\.name))
        return fields
    }
}

enum AttentionSelectionStabilityPolicy {
    static func stabilizing(
        requestedSelection: Set<AttentionItem.ID>,
        currentSelection: Set<AttentionItem.ID>,
        displayedItemIDs: Set<AttentionItem.ID>
    ) -> Set<AttentionItem.ID> {
        let normalizedRequested = requestedSelection.intersection(displayedItemIDs)
        guard normalizedRequested.isEmpty else {
            return normalizedRequested
        }

        let normalizedCurrent = currentSelection.intersection(displayedItemIDs)
        guard !normalizedCurrent.isEmpty else {
            return []
        }

        return normalizedCurrent
    }

    static func stabilizing(
        requestedSelection: Set<AttentionItem.ID>,
        currentSelection: Set<AttentionItem.ID>,
        rememberedSubjectKeys: Set<String>,
        displayedItems: [AttentionItem]
    ) -> Set<AttentionItem.ID> {
        let displayedItemIDs = Set(displayedItems.map(\.id))
        let normalizedSelection = stabilizing(
            requestedSelection: requestedSelection,
            currentSelection: currentSelection,
            displayedItemIDs: displayedItemIDs
        )
        guard normalizedSelection.isEmpty else {
            return normalizedSelection
        }

        guard !rememberedSubjectKeys.isEmpty else {
            return []
        }

        return Set(
            displayedItems
                .filter { rememberedSubjectKeys.contains($0.subjectKey) }
                .map(\.id)
        )
    }

    static func retainingRememberedSubjectKeys(
        from currentSubjectKeys: Set<String>,
        selection: Set<AttentionItem.ID>,
        displayedItems: [AttentionItem]
    ) -> Set<String> {
        let selectedSubjectKeys = Set(
            displayedItems
                .filter { selection.contains($0.id) }
                .map(\.subjectKey)
        )
        guard selectedSubjectKeys.isEmpty else {
            return selectedSubjectKeys
        }

        let visibleSubjectKeys = Set(displayedItems.map(\.subjectKey))
        return currentSubjectKeys.intersection(visibleSubjectKeys)
    }

    static func preferredAutoSelectionItemID(
        rememberedSubjectKeys: Set<String>,
        displayedItems: [AttentionItem]
    ) -> AttentionItem.ID? {
        if let rememberedItem = displayedItems.first(
            where: { rememberedSubjectKeys.contains($0.subjectKey) }
        ) {
            return rememberedItem.id
        }

        return displayedItems.first?.id
    }
}

enum AttentionSelectionRequestPolicy {
    static func itemID(
        for subjectKey: String,
        in items: [AttentionItem]
    ) -> AttentionItem.ID? {
        items.first(where: { $0.subjectKey == subjectKey })?.id
    }
}

enum AttentionEmptyStateAction: Hashable, Sendable {
    case showAllInboxItems
    case showPullRequests
    case showIssues
    case openSnoozedItems
    case openIgnoredItems

    var title: String {
        switch self {
        case .showAllInboxItems:
            return "Show All"
        case .showPullRequests:
            return "Show My PRs"
        case .showIssues:
            return "Show My Issues"
        case .openSnoozedItems:
            return "Open Snoozed Items"
        case .openIgnoredItems:
            return "Open Ignored Items"
        }
    }
}

struct AttentionEmptyStateContent: Hashable, Sendable {
    let title: String
    let description: String
    let actions: [AttentionEmptyStateAction]
}

enum AttentionEmptyStatePolicy {
    static func inbox(
        showsUnreadOnly: Bool,
        snoozedCount: Int,
        ignoredCount: Int,
        pullRequestCount: Int,
        issueCount: Int
    ) -> AttentionEmptyStateContent {
        var actions = [AttentionEmptyStateAction]()
        if showsUnreadOnly {
            actions.append(.showAllInboxItems)
        }

        let hiddenSummary = hiddenSummary(
            snoozedCount: snoozedCount,
            ignoredCount: ignoredCount
        )
        let browseSummary = browseSummary(
            pullRequestCount: pullRequestCount,
            issueCount: issueCount
        )

        if showsUnreadOnly {
            if snoozedCount > 0 {
                actions.append(.openSnoozedItems)
            }
            if ignoredCount > 0 {
                actions.append(.openIgnoredItems)
            }

            var description = "Everything currently in the inbox has been marked read."
            if let hiddenSummary {
                description += " \(hiddenSummary)"
            }

            return AttentionEmptyStateContent(
                title: "No unread items",
                description: description,
                actions: actions
            )
        }

        if pullRequestCount > 0 {
            actions.append(.showPullRequests)
        }
        if issueCount > 0 {
            actions.append(.showIssues)
        }
        if snoozedCount > 0 {
            actions.append(.openSnoozedItems)
        }
        if ignoredCount > 0 {
            actions.append(.openIgnoredItems)
        }

        var descriptionParts = [String]()

        if let browseSummary {
            descriptionParts.append(
                "Nothing currently qualifies for the inbox, but Browse still has \(browseSummary)."
            )
        } else {
            descriptionParts.append(
                "Octowatch is watching GitHub, but there is nothing actionable right now."
            )
        }

        if let hiddenSummary {
            descriptionParts.append(hiddenSummary)
        }

        return AttentionEmptyStateContent(
            title: "Inbox is clear",
            description: descriptionParts.joined(separator: " "),
            actions: actions
        )
    }

    private static func hiddenSummary(
        snoozedCount: Int,
        ignoredCount: Int
    ) -> String? {
        var parts = [String]()

        if snoozedCount > 0 {
            let noun = snoozedCount == 1 ? "item is" : "items are"
            parts.append("\(snoozedCount) \(noun) snoozed locally")
        }

        if ignoredCount > 0 {
            let noun = ignoredCount == 1 ? "item is" : "items are"
            parts.append("\(ignoredCount) \(noun) ignored locally")
        }

        guard !parts.isEmpty else {
            return nil
        }

        if parts.count == 1 {
            return "\(parts[0])."
        }

        return "\(parts[0]) and \(parts[1])."
    }

    private static func browseSummary(
        pullRequestCount: Int,
        issueCount: Int
    ) -> String? {
        var parts = [String]()

        if pullRequestCount > 0 {
            let noun = pullRequestCount == 1 ? "pull request" : "pull requests"
            parts.append("\(pullRequestCount) \(noun)")
        }

        if issueCount > 0 {
            let noun = issueCount == 1 ? "issue" : "issues"
            parts.append("\(issueCount) \(noun)")
        }

        guard !parts.isEmpty else {
            return nil
        }

        if parts.count == 1 {
            return parts[0]
        }

        return "\(parts[0]) and \(parts[1])"
    }
}

enum InboxSectionPolicy {
    private static let selfReviewTypes: Set<AttentionItemType> = [
        .reviewApproved,
        .reviewChangesRequested,
        .reviewComment
    ]

    static func matchingItems(
        in items: [AttentionItem],
        configuration: InboxSectionConfiguration,
        acknowledgedWorkflows: [String: AcknowledgedWorkflowState] = [:]
    ) -> [AttentionItem] {
        let enabledRules = configuration.enabledRules
        return items.filter { item in
            guard !item.isHistoricalLogEntry else {
                return false
            }

            if let ack = acknowledgedWorkflows[item.subjectKey],
               item.type.isWorkflowActivityType,
               ack.coversRunID(item.latestSourceID) {
                return false
            }

            let derivedFacts = facts(for: item)
            return enabledRules.contains(where: { matches(item, facts: derivedFacts, rule: $0) })
        }
    }

    struct SectionResult: Equatable {
        let name: String
        let items: [AttentionItem]
    }

    static func matchingItemsBySection(
        in items: [AttentionItem],
        configuration: InboxSectionConfiguration,
        acknowledgedWorkflows: [String: AcknowledgedWorkflowState] = [:]
    ) -> [SectionResult] {
        var seen = Set<String>()
        var results = [SectionResult]()

        for section in configuration.sections {
            let sectionRules = section.enabledRules.map(\.normalized)
            guard !sectionRules.isEmpty else { continue }

            var sectionItems = [AttentionItem]()

            for item in items {
                guard !item.isHistoricalLogEntry else { continue }
                guard !seen.contains(item.id) else { continue }

                if let ack = acknowledgedWorkflows[item.subjectKey],
                   item.type.isWorkflowActivityType,
                   ack.coversRunID(item.latestSourceID) {
                    continue
                }

                let derivedFacts = facts(for: item)
                if sectionRules.contains(where: { matches(item, facts: derivedFacts, rule: $0) }) {
                    seen.insert(item.id)
                    sectionItems.append(item)
                }
            }

            if !sectionItems.isEmpty {
                results.append(SectionResult(name: section.name, items: sectionItems))
            }
        }

        return results
    }

    static func matchingRules(
        for item: AttentionItem,
        configuration: InboxSectionConfiguration
    ) -> [InboxSectionRule] {
        let facts = facts(for: item)
        return configuration.enabledRules.filter { rule in
            matches(item, facts: facts, rule: rule)
        }
    }

    private static func matches(
        _ item: AttentionItem,
        facts: InboxRuleFacts,
        rule: InboxSectionRule
    ) -> Bool {
        let normalizedRule = rule.normalized

        guard normalizedRule.isEnabled else {
            return false
        }

        guard facts.itemKinds.contains(normalizedRule.itemKind) else {
            return false
        }

        guard !normalizedRule.conditions.isEmpty else {
            return true
        }

        let evaluations = normalizedRule.conditions.map { condition in
            matches(facts: facts, condition: condition)
        }

        return evaluations.allSatisfy { $0 }
    }

    private static func matches(
        facts: InboxRuleFacts,
        condition: InboxRuleCondition
    ) -> Bool {
        let expandedRelationships = condition.relationshipValues.reduce(into: Set<InboxRuleRelationship>()) {
            $0.formUnion($1.expandedRelationships)
        }
        let baseMatch: Bool = switch condition.kind {
        case .relationship:
            !facts.relationships.intersection(expandedRelationships).isEmpty
        case .signal:
            !facts.signals.intersection(condition.signalValues).isEmpty
        case .viewerReview:
            switch condition.viewerReviewValue {
            case .missing:
                facts.hasViewerReview == false
            case .present:
                facts.hasViewerReview
            }
        }

        return condition.isNegated ? !baseMatch : baseMatch
    }

    private static func hasViewerReviewUpdate(in item: AttentionItem) -> Bool {
        if item.isTriggeredByCurrentUser && selfReviewTypes.contains(item.type) {
            return true
        }

        return item.detail.updates.contains { update in
            update.isTriggeredByCurrentUser && selfReviewTypes.contains(update.type)
        }
    }

    private static func facts(for item: AttentionItem) -> InboxRuleFacts {
        var signals = item.currentUpdateTypes.reduce(into: Set<InboxRuleSignal>()) { partialResult, type in
            switch type {
            case .readyToMerge:
                partialResult.insert(.readyToMerge)
                partialResult.insert(.readyForReview)
            case .pullRequestMergeConflicts:
                partialResult.insert(.mergeConflicts)
            case .pullRequestFailedChecks:
                partialResult.insert(.failedChecks)
            case .workflowFailed:
                partialResult.insert(.workflowFailed)
            case .workflowApprovalRequired:
                partialResult.insert(.workflowApprovalRequired)
            case .workflowRunning:
                partialResult.insert(.workflowRunning)
            default:
                break
            }
        }

        if item.pullRequestReference != nil, item.isDraft == false {
            signals.insert(.readyForReview)
        }

        let relationships = relationshipTypes(in: item).reduce(
            into: Set<InboxRuleRelationship>()
        ) { partialResult, type in
            switch type {
            case .authoredPullRequest, .authoredIssue:
                partialResult.insert(.authored)
            case .assignedPullRequest, .assignedIssue:
                partialResult.insert(.assigned)
            case .reviewedPullRequest:
                partialResult.insert(.reviewed)
            case .commentedPullRequest, .commentedIssue:
                partialResult.insert(.commented)
            default:
                break
            }
        }

        var itemKinds = Set<InboxRuleItemKind>()
        let isOpenSubject = item.subjectResolution == nil || item.subjectResolution == .open

        if item.currentUpdateTypes.contains(where: \.isWorkflowActivityType) {
            itemKinds.insert(.workflow)
        }

        if isOpenSubject, item.pullRequestReference != nil {
            itemKinds.insert(.pullRequest)
        }
        if isOpenSubject, item.subjectReference?.kind == .issue {
            itemKinds.insert(.issue)
        }

        return InboxRuleFacts(
            itemKinds: itemKinds,
            relationships: relationships,
            signals: signals,
            hasViewerReview: hasViewerReviewUpdate(in: item)
        )
    }

    private static func relationshipTypes(in item: AttentionItem) -> Set<AttentionItemType> {
        var result = item.currentRelationshipTypes
        if item.type.isRelationshipType {
            result.insert(item.type)
        }

        if let focusType = item.focusType, focusType.isRelationshipType {
            result.insert(focusType)
        }
        if let secondaryIndicatorType = item.secondaryIndicatorType,
            secondaryIndicatorType.isRelationshipType {
            result.insert(secondaryIndicatorType)
        }

        return result
    }
}

enum NotificationAttentionPolicy {
    private static let directReasons: Set<String> = [
        "assign",
        "mention",
        "review_requested",
        "security_alert",
        "team_mention"
    ]

    private static let discussionReasons: Set<String> = [
        "author",
        "comment",
        "state_change"
    ]

    static func isActionable(reason: String) -> Bool {
        let normalizedReason = reason.lowercased()
        return directReasons.contains(normalizedReason) ||
            discussionReasons.contains(normalizedReason)
    }

    static func shouldIncludeFallback(
        reason: String,
        updatedAt: Date,
        now: Date = Date()
    ) -> Bool {
        let normalizedReason = reason.lowercased()

        if directReasons.contains(normalizedReason) {
            return true
        }

        guard discussionReasons.contains(normalizedReason) else {
            return false
        }

        return updatedAt >= now.addingTimeInterval(-86_400)
    }

    static func shouldIncludePullRequestFallback(
        state: String,
        merged: Bool
    ) -> Bool {
        state.lowercased() == "open" && !merged
    }
}

enum AuthoredPullRequestAttentionPolicy {
    static func shouldSurfaceReadyToMerge(
        state: String,
        merged: Bool,
        isDraft: Bool,
        mergeable: Bool?,
        mergeableState: String?,
        pendingReviewRequests: Int,
        approvalCount: Int,
        hasChangesRequested: Bool,
        checkSummary: PullRequestCheckSummary
    ) -> Bool {
        guard state.lowercased() == "open", !merged, !isDraft else {
            return false
        }

        guard mergeable == true, mergeableState?.lowercased() == "clean" else {
            return false
        }

        guard pendingReviewRequests == 0, approvalCount > 0, !hasChangesRequested else {
            return false
        }

        return checkSummary.totalCount > 0 && checkSummary.isClear
    }

    static func shouldSurfaceMergeConflicts(
        state: String,
        merged: Bool,
        isDraft: Bool,
        mergeableState: String?
    ) -> Bool {
        guard state.lowercased() == "open", !merged else {
            return false
        }

        return mergeableState?.lowercased() == "dirty"
    }

    static func shouldSurfaceFailedChecks(
        state: String,
        merged: Bool,
        isDraft: Bool,
        checkSummary: PullRequestCheckSummary
    ) -> Bool {
        guard state.lowercased() == "open", !merged else {
            return false
        }

        return checkSummary.hasFailures
    }
}

enum PullRequestAttentionPolicy {
    private static let mergedWorkflowWatchWindow: TimeInterval = 7 * 86_400

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

        return mergedAt >= now.addingTimeInterval(-mergedWorkflowWatchWindow)
    }
}

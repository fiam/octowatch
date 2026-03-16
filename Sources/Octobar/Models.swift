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

enum AttentionItemType: String, Hashable, Sendable {
    case assignedPullRequest
    case authoredPullRequest
    case reviewedPullRequest
    case commentedPullRequest
    case readyToMerge
    case assignedIssue
    case authoredIssue
    case commentedIssue
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
        case .assignedIssue:
            return "exclamationmark.circle"
        case .authoredIssue:
            return "exclamationmark.circle"
        case .commentedIssue:
            return "exclamationmark.circle"
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
        case .assignedIssue:
            return "Assigned issue"
        case .authoredIssue:
            return "Your issue"
        case .commentedIssue:
            return "Commented issue"
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
        case .assignedIssue:
            return "Issue assigned"
        case .authoredIssue:
            return "Your issue"
        case .commentedIssue:
            return "Commented issue"
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
        case .assignedIssue:
            return "assigned an issue"
        case .authoredIssue:
            return "updated your issue"
        case .commentedIssue:
            return "updated an issue you commented on"
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

    var defaultStream: AttentionStream {
        switch self {
        case .assignedPullRequest,
                .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .readyToMerge,
                .ciActivity,
                .workflowFailed,
                .workflowApprovalRequired:
            return .pullRequests
        case .assignedIssue,
                .authoredIssue,
                .commentedIssue:
            return .issues
        case .comment,
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

struct AttentionActor: Hashable, Sendable {
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
}

enum NotificationFollowUpRelationship: Hashable, Sendable {
    case afterYourComment
    case afterYourReview
}

struct AttentionWhy: Hashable, Sendable {
    let summary: String
    let detail: String?
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

struct AttentionDetail: Hashable, Sendable {
    let why: AttentionWhy
    let evidence: [AttentionEvidence]
    let actions: [AttentionAction]
    let acknowledgement: String?
}

struct PullRequestReference: Hashable, Sendable {
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
}

enum GitHubSubjectResolution: Hashable, Sendable {
    case open
    case closed
    case merged
}

struct GitHubSubjectResolutionState: Hashable, Sendable {
    let reference: GitHubSubjectReference
    let resolution: GitHubSubjectResolution
    let isAssignedToViewer: Bool?
}

struct AttentionTransitionNotification: Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let body: String
    let url: URL
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
                title: "Pull request unassigned",
                subtitle: representative.title,
                body: "This pull request is no longer assigned to you in \(representative.repository ?? state.reference.repository).",
                url: state.reference.webURL
            )
        }
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
    let sourceType: AttentionItemType
    let mode: PullRequestFocusMode
    let author: AttentionActor?
    let headerFacts: [PullRequestHeaderFact]
    let contextBadges: [PullRequestContextBadge]
    let descriptionHTML: String?
    let statusSummary: PullRequestStatusSummary?
    let sections: [PullRequestFocusSection]
    let actions: [AttentionAction]
    let reviewMergeAction: PullRequestReviewMergeAction?
    let emptyStateTitle: String
    let emptyStateDetail: String
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
    let rateLimit: GitHubRateLimit?
}

struct PullRequestContextBadge: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let iconName: String
    let accent: PullRequestFocusEntryAccent
}

struct PullRequestReviewMergeAction: Hashable, Sendable {
    let title: String
    let requiresApproval: Bool
    let isEnabled: Bool
    let disabledReason: String?

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
        for sourceType: AttentionItemType,
        author: AttentionActor?
    ) -> [PullRequestContextBadge] {
        []
    }
}

extension PullRequestHeaderFact {
    static func build(
        sourceType: AttentionItemType,
        author: AttentionActor?,
        assigner: AttentionActor?,
        latestApprover: AttentionActor?,
        approvalCount: Int
    ) -> [PullRequestHeaderFact] {
        switch sourceType {
        case .readyToMerge:
            guard let latestApprover else {
                return []
            }

            return [
                PullRequestHeaderFact(
                    id: "approved-by",
                    label: "approved by",
                    actor: latestApprover,
                    additionalActorCount: max(0, approvalCount - 1)
                )
            ]

        case .assignedPullRequest:
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
        mergeable: String?,
        isDraft: Bool,
        reviewDecision: String?,
        approvalCount: Int,
        hasChangesRequested: Bool,
        pendingReviewRequestCount: Int,
        checkSummary: PullRequestCheckSummary,
        openThreadCount: Int
    ) -> PullRequestReviewMergeAction? {
        let isBotReviewablePullRequest =
            [
                AttentionItemType.assignedPullRequest,
                .reviewRequested,
                .teamReviewRequested
            ].contains(sourceType) && author?.isBotAccount == true
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

        if !PullRequestRepositoryPermissionPolicy.canMergeOrApprove(viewerPermission: viewerPermission) {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: requiresApproval
                    ? "You do not have permission to review and merge pull requests in this repository."
                    : "You do not have permission to merge pull requests in this repository."
            )
        }

        if isDraft {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "This pull request is still a draft."
            )
        }

        if mergeable?.caseInsensitiveCompare("MERGEABLE") != .orderedSame {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "GitHub does not consider this pull request mergeable yet."
            )
        }

        if hasChangesRequested {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "Changes have been requested on this pull request."
            )
        }

        if pendingReviewRequestCount > 0 && !allowsCurrentReviewRequestToBeSatisfied {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: pendingReviewRequestCount == 1
                    ? "A review is still requested on this pull request."
                    : "Reviews are still requested on this pull request."
            )
        }

        if openThreadCount > 0 {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "Resolve the open review conversations first."
            )
        }

        if checkSummary.hasFailures {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "Some checks are failing."
            )
        }

        if checkSummary.hasPending {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "Checks are still running."
            )
        }

        if !requiresApproval && !hasApproval {
            return PullRequestReviewMergeAction(
                title: title,
                requiresApproval: requiresApproval,
                isEnabled: false,
                disabledReason: "This pull request still needs an approving review."
            )
        }

        return PullRequestReviewMergeAction(
            title: title,
            requiresApproval: requiresApproval,
            isEnabled: true,
            disabledReason: nil
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
                    title: "View Commits",
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
        checkSummary: PullRequestCheckSummary,
        openThreadCount: Int,
        reviewMergeAction: PullRequestReviewMergeAction?
    ) -> PullRequestStatusSummary? {
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
    let ignoreKey: String
    let stream: AttentionStream
    let type: AttentionItemType
    let title: String
    let subtitle: String
    let repository: String?
    let timestamp: Date
    let url: URL
    let actor: AttentionActor?
    let detail: AttentionDetail
    var isUnread: Bool

    init(
        id: String,
        ignoreKey: String,
        stream: AttentionStream? = nil,
        type: AttentionItemType,
        title: String,
        subtitle: String,
        repository: String? = nil,
        timestamp: Date,
        url: URL,
        actor: AttentionActor? = nil,
        detail: AttentionDetail? = nil,
        isUnread: Bool = true
    ) {
        self.id = id
        self.ignoreKey = ignoreKey
        self.stream = stream ?? type.defaultStream
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.repository = repository
        self.timestamp = timestamp
        self.url = url
        self.actor = actor
        self.detail = detail ?? Self.defaultDetail(
            type: type,
            subtitle: subtitle,
            url: url,
            actor: actor
        )
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

    var isClosureNotificationEligible: Bool {
        switch type {
        case .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .readyToMerge,
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
                .ciActivity,
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
        case .assignedIssue:
            return "This issue is assigned to you."
        case .authoredIssue:
            return "You opened this issue."
        case .commentedIssue:
            return "You commented on this issue."
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

struct TrackedSubjectSummary: Identifiable, Hashable, Sendable {
    let id: String
    let ignoreKey: String
    let type: AttentionItemType
    let number: Int
    let title: String
    let subtitle: String
    let repository: String
    let url: URL
    let updatedAt: Date
}

struct ReadyToMergeSummary: Identifiable, Hashable, Sendable {
    let id: String
    let ignoreKey: String
    let number: Int
    let title: String
    let subtitle: String
    let repository: String
    let url: URL
    let updatedAt: Date
    let actor: AttentionActor?
    let approvalCount: Int
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
    let targetLabel: String?
    let detailEvidence: [AttentionEvidence]
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

struct GitHubSnapshot: Sendable {
    let login: String
    let attentionItems: [AttentionItem]
    let rateLimit: GitHubRateLimit?
    let notificationScanState: NotificationScanState
    let teamMembershipCache: TeamMembershipCache
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

struct IgnoreUndoState: Identifiable, Hashable, Sendable {
    let subject: IgnoredAttentionSubject
    let expiresAt: Date

    var id: String { subject.id }
}

enum AttentionItemVisibilityPolicy {
    static func excludingIgnoredSubjects(
        _ items: [AttentionItem],
        ignoredKeys: Set<String>
    ) -> [AttentionItem] {
        items.filter { !ignoredKeys.contains($0.ignoreKey) }
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
        hasChangesRequested: Bool
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

        return true
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

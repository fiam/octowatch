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

private struct AttentionCombinedDisplayKey: Hashable {
    let ignoreKey: String
    let type: AttentionItemType
}

enum AttentionCombinedViewPolicy {
    static func collapsingDuplicates(in items: [AttentionItem]) -> [AttentionItem] {
        var preferredByKey = [AttentionCombinedDisplayKey: AttentionItem]()

        for item in items {
            let key = AttentionCombinedDisplayKey(ignoreKey: item.ignoreKey, type: item.type)
            if let existing = preferredByKey[key], !shouldReplace(existing: existing, with: item) {
                continue
            }

            preferredByKey[key] = item
        }

        var emitted = Set<AttentionItem.ID>()
        return items.compactMap { item in
            let key = AttentionCombinedDisplayKey(ignoreKey: item.ignoreKey, type: item.type)
            guard let preferred = preferredByKey[key], preferred.id == item.id else {
                return nil
            }

            guard emitted.insert(item.id).inserted else {
                return nil
            }

            return item
        }
    }

    private static func shouldReplace(existing: AttentionItem, with candidate: AttentionItem) -> Bool {
        if existing.stream != .notifications && candidate.stream == .notifications {
            return true
        }

        if existing.stream == .notifications && candidate.stream != .notifications {
            return false
        }

        if existing.isUnread != candidate.isUnread {
            return candidate.isUnread
        }

        if existing.timestamp != candidate.timestamp {
            return candidate.timestamp > existing.timestamp
        }

        if existing.actor == nil && candidate.actor != nil {
            return true
        }

        return candidate.detail.evidence.count > existing.detail.evidence.count
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
    let contextPillTitle: String?
    let why: AttentionWhy
    let evidence: [AttentionEvidence]
    let actions: [AttentionAction]
    let acknowledgement: String?

    init(
        contextPillTitle: String? = nil,
        why: AttentionWhy,
        evidence: [AttentionEvidence],
        actions: [AttentionAction],
        acknowledgement: String? = nil
    ) {
        self.contextPillTitle = contextPillTitle
        self.why = why
        self.evidence = evidence
        self.actions = actions
        self.acknowledgement = acknowledgement
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
    let rateLimit: GitHubRateLimit?
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
    let rateLimit: GitHubRateLimit?
}

struct PostMergeWatchUpdate: Hashable, Sendable {
    let updatedWatch: PostMergeWatch?
    let notifications: [AttentionTransitionNotification]
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
                        pullRequestTitle: watch.title
                    )
                {
                    notifications.append(notification)
                    notifiedApprovalRequiredRunIDs.insert(run.id)
                    suppressedItemIDs.insert(run.attentionItemID)
                }

                guard
                    (run.status ?? "").caseInsensitiveCompare("completed") == .orderedSame,
                    !notifiedRunIDs.contains(run.id),
                    let notification = workflowCompletionNotification(for: run, pullRequestTitle: watch.title)
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
                hasPendingRuns: pushRuns.contains {
                    ($0.status ?? "").caseInsensitiveCompare("completed") != .orderedSame
                },
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
        pullRequestTitle: String
    ) -> AttentionTransitionNotification? {
        let normalizedConclusion = (run.conclusion ?? "").lowercased()
        let title: String
        let body: String

        switch normalizedConclusion {
        case "success":
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
            title: title,
            subtitle: run.title,
            body: body,
            url: run.url
        )
    }

    private static func workflowRequiresApproval(_ run: PostMergeObservedWorkflowRun) -> Bool {
        let normalizedStatus = (run.status ?? "").lowercased()
        let normalizedConclusion = (run.conclusion ?? "").lowercased()

        return normalizedStatus == "action_required" || normalizedConclusion == "action_required"
    }

    private static func workflowApprovalRequiredNotification(
        for run: PostMergeObservedWorkflowRun,
        pullRequestTitle: String
    ) -> AttentionTransitionNotification? {
        guard workflowRequiresApproval(run) else {
            return nil
        }

        return AttentionTransitionNotification(
            id: "post-merge:workflow-approval:\(run.repository):\(run.id)",
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
    let author: AttentionActor?
    let headerFacts: [PullRequestHeaderFact]
    let contextBadges: [PullRequestContextBadge]
    let descriptionHTML: String?
    let statusSummary: PullRequestStatusSummary?
    let postMergeWorkflowPreview: PullRequestPostMergeWorkflowPreview?
    let sections: [PullRequestFocusSection]
    let actions: [AttentionAction]
    let reviewMergeAction: PullRequestReviewMergeAction?
    let emptyStateTitle: String
    let emptyStateDetail: String
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

    static func observed(status: String?, conclusion: String?) -> PullRequestPostMergeWorkflowStatus {
        let normalizedStatus = (status ?? "").lowercased()
        let normalizedConclusion = (conclusion ?? "").lowercased()

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
    let isBestEffort: Bool

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
        guard isBestEffort else {
            return nil
        }

        return "Some workflow files could not be parsed, so this list may be incomplete."
    }
}

struct PullRequestPostMergeWorkflow: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let url: URL
    let status: PullRequestPostMergeWorkflowStatus
    let timestamp: Date?
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
    let rateLimit: GitHubRateLimit?
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
            author: author,
            headerFacts: headerFacts,
            contextBadges: contextBadges,
            descriptionHTML: descriptionHTML,
            statusSummary: statusSummary,
            postMergeWorkflowPreview: postMergeWorkflowPreview,
            sections: sections,
            actions: actions,
            reviewMergeAction: reviewMergeAction?.applyingPreferredMergeMethod(mergeMethod),
            emptyStateTitle: emptyStateTitle,
            emptyStateDetail: emptyStateDetail
        )
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
    static func badges(workflowAttentionType: AttentionItemType?) -> [PullRequestContextBadge] {
        guard let workflowAttentionType else {
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
            guard let approver = sourceActor ?? latestApprover else {
                return []
            }

            return [
                PullRequestHeaderFact(
                    id: "approved-by",
                    label: "approved by",
                    actor: approver,
                    additionalActorCount: max(0, approvalCount - 1)
                )
            ]

        case .reviewApproved:
            guard let approver = sourceActor ?? latestApprover else {
                return []
            }

            return [
                PullRequestHeaderFact(
                    id: "approved-by",
                    label: "approved by",
                    actor: approver,
                    additionalActorCount: 0
                )
            ]

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
    let ignoreKey: String
    let stream: AttentionStream
    let type: AttentionItemType
    let secondaryIndicatorType: AttentionItemType?
    let title: String
    let subtitle: String
    let repository: String?
    let timestamp: Date
    let url: URL
    let actor: AttentionActor?
    let detail: AttentionDetail
    let isHistoricalLogEntry: Bool
    var isUnread: Bool

    init(
        id: String,
        ignoreKey: String,
        stream: AttentionStream? = nil,
        type: AttentionItemType,
        secondaryIndicatorType: AttentionItemType? = nil,
        title: String,
        subtitle: String,
        repository: String? = nil,
        timestamp: Date,
        url: URL,
        actor: AttentionActor? = nil,
        detail: AttentionDetail? = nil,
        isHistoricalLogEntry: Bool = false,
        isUnread: Bool = true
    ) {
        self.id = id
        self.ignoreKey = ignoreKey
        self.stream = stream ?? type.defaultStream
        self.type = type
        self.secondaryIndicatorType = secondaryIndicatorType
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
        self.isHistoricalLogEntry = isHistoricalLogEntry
        self.isUnread = isUnread
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

    var isPostMergeWatchEligible: Bool {
        guard pullRequestReference != nil else {
            return false
        }

        switch type {
        case .assignedPullRequest,
                .reviewRequested,
                .teamReviewRequested,
                .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .readyToMerge,
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
    let url: URL
    let updatedAt: Date
    let actor: AttentionActor?
    let resolution: GitHubSubjectResolution
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
    let subjects: [IgnoredAttentionSubject]
    let expiresAt: Date

    var id: String {
        subjects.map(\.ignoreKey).sorted().joined(separator: "|")
    }

    var primarySubject: IgnoredAttentionSubject? {
        subjects.first
    }
}

enum AttentionItemVisibilityPolicy {
    static func excludingIgnoredSubjects(
        _ items: [AttentionItem],
        ignoredKeys: Set<String>
    ) -> [AttentionItem] {
        items.filter { !ignoredKeys.contains($0.ignoreKey) }
    }

    static func excludingHistoricalLogEntries(
        _ items: [AttentionItem]
    ) -> [AttentionItem] {
        items.filter { !$0.isHistoricalLogEntry }
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

struct GitHubWorkflowPushTrigger: Hashable, Sendable {
    let branches: [String]
    let branchesIgnore: [String]
    let paths: [String]
    let pathsIgnore: [String]

    static let `default` = GitHubWorkflowPushTrigger(
        branches: [],
        branchesIgnore: [],
        paths: [],
        pathsIgnore: []
    )
}

struct GitHubWorkflowFileDefinition: Hashable, Sendable {
    let name: String?
    let pushTrigger: GitHubWorkflowPushTrigger?
}

enum GitHubWorkflowFileParser {
    static func parse(_ content: String) -> GitHubWorkflowFileDefinition? {
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        var parsedLines = [ParsedLine]()
        parsedLines.reserveCapacity(lines.count)

        for rawLine in lines {
            guard let parsedLine = ParsedLine(rawLine) else {
                continue
            }
            parsedLines.append(parsedLine)
        }

        guard !parsedLines.isEmpty else {
            return nil
        }

        var workflowName: String?
        var onLineIndex: Int?

        for (index, line) in parsedLines.enumerated() {
            guard line.indent == 0, let keyValue = line.keyValue else {
                continue
            }

            let key = normalizedKey(keyValue.key)
            if key == "name", workflowName == nil {
                workflowName = scalarValues(from: keyValue.value).first
            } else if key == "on" {
                onLineIndex = index
                break
            }
        }

        guard let onLineIndex else {
            return GitHubWorkflowFileDefinition(name: workflowName, pushTrigger: nil)
        }

        let onLine = parsedLines[onLineIndex]
        let pushTrigger: GitHubWorkflowPushTrigger?
        if let value = onLine.keyValue?.value, !value.isEmpty {
            let events = scalarValues(from: value).map { $0.lowercased() }
            pushTrigger = events.contains("push") ? .default : nil
        } else {
            pushTrigger = parseOnBlock(
                parsedLines,
                startIndex: onLineIndex + 1,
                parentIndent: onLine.indent
            )
        }

        return GitHubWorkflowFileDefinition(name: workflowName, pushTrigger: pushTrigger)
    }

    private static func parseOnBlock(
        _ lines: [ParsedLine],
        startIndex: Int,
        parentIndent: Int
    ) -> GitHubWorkflowPushTrigger? {
        var pushTrigger: GitHubWorkflowPushTrigger?

        var index = startIndex
        while index < lines.count {
            let line = lines[index]
            guard line.indent > parentIndent else {
                break
            }

            guard let keyValue = line.keyValue else {
                index += 1
                continue
            }

            let key = normalizedKey(keyValue.key)
            if key == "push" {
                if keyValue.value.isEmpty {
                    pushTrigger = parsePushBlock(
                        lines,
                        startIndex: index + 1,
                        parentIndent: line.indent
                    ) ?? .default
                } else {
                    pushTrigger = .default
                }
                break
            }

            index += 1
        }

        return pushTrigger
    }

    private static func parsePushBlock(
        _ lines: [ParsedLine],
        startIndex: Int,
        parentIndent: Int
    ) -> GitHubWorkflowPushTrigger? {
        var branches = [String]()
        var branchesIgnore = [String]()
        var paths = [String]()
        var pathsIgnore = [String]()
        var sawFilter = false

        var index = startIndex
        while index < lines.count {
            let line = lines[index]
            guard line.indent > parentIndent else {
                break
            }

            guard let keyValue = line.keyValue else {
                index += 1
                continue
            }

            let key = normalizedKey(keyValue.key)
            let values: [String]
            if keyValue.value.isEmpty {
                let sequence = blockSequence(
                    lines,
                    startIndex: index + 1,
                    parentIndent: line.indent
                )
                values = sequence.values
                index = sequence.nextIndex
            } else {
                values = scalarValues(from: keyValue.value)
                index += 1
            }

            switch key {
            case "branches":
                branches = values
                sawFilter = true
            case "branches-ignore":
                branchesIgnore = values
                sawFilter = true
            case "paths":
                paths = values
                sawFilter = true
            case "paths-ignore":
                pathsIgnore = values
                sawFilter = true
            default:
                break
            }
        }

        guard sawFilter else {
            return nil
        }

        return GitHubWorkflowPushTrigger(
            branches: branches,
            branchesIgnore: branchesIgnore,
            paths: paths,
            pathsIgnore: pathsIgnore
        )
    }

    private static func normalizedKey(_ key: String) -> String {
        normalizeScalar(key).lowercased()
    }

    private static func scalarValues(from rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            return splitCommaSeparated(inner).map(normalizeScalar)
        }

        return [normalizeScalar(trimmed)]
    }

    private static func normalizeScalar(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func splitCommaSeparated(_ value: String) -> [String] {
        var result = [String]()
        var current = ""
        var insideSingleQuotes = false
        var insideDoubleQuotes = false

        for character in value {
            switch character {
            case "'" where !insideDoubleQuotes:
                insideSingleQuotes.toggle()
                current.append(character)
            case "\"" where !insideSingleQuotes:
                insideDoubleQuotes.toggle()
                current.append(character)
            case "," where !insideSingleQuotes && !insideDoubleQuotes:
                result.append(current)
                current = ""
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }

    private static func blockSequence(
        _ lines: [ParsedLine],
        startIndex: Int,
        parentIndent: Int
    ) -> (values: [String], nextIndex: Int) {
        var values = [String]()
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            guard line.indent > parentIndent else {
                break
            }

            if let listItem = line.listItem {
                values.append(normalizeScalar(listItem))
                index += 1
                continue
            }

            if line.keyValue != nil, line.indent == parentIndent + 2 {
                break
            }

            index += 1
        }

        return (values, index)
    }

    private struct ParsedLine {
        let indent: Int
        let content: String

        init?(_ rawLine: String) {
            let expanded = rawLine.replacingOccurrences(of: "\t", with: "  ")
            let withoutComment = Self.removingComment(from: expanded)
            let trimmed = withoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            indent = withoutComment.prefix { $0 == " " }.count
            content = trimmed
        }

        var keyValue: (key: String, value: String)? {
            var insideSingleQuotes = false
            var insideDoubleQuotes = false

            for character in content {
                switch character {
                case "'" where !insideDoubleQuotes:
                    insideSingleQuotes.toggle()
                case "\"" where !insideSingleQuotes:
                    insideDoubleQuotes.toggle()
                case ":" where !insideSingleQuotes && !insideDoubleQuotes:
                    let parts = content.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2 else {
                        return nil
                    }

                    return (
                        key: String(parts[0]),
                        value: String(parts[1])
                    )
                default:
                    break
                }
            }

            return nil
        }

        var listItem: String? {
            guard content.hasPrefix("- ") else {
                return nil
            }

            return String(content.dropFirst(2))
        }

        private static func removingComment(from line: String) -> String {
            var result = ""
            var insideSingleQuotes = false
            var insideDoubleQuotes = false
            var previous: Character?

            for character in line {
                switch character {
                case "'" where !insideDoubleQuotes:
                    insideSingleQuotes.toggle()
                    result.append(character)
                case "\"" where !insideSingleQuotes:
                    insideDoubleQuotes.toggle()
                    result.append(character)
                case "#" where !insideSingleQuotes && !insideDoubleQuotes && (previous == nil || previous?.isWhitespace == true):
                    return result
                default:
                    result.append(character)
                }

                previous = character
            }

            return result
        }
    }
}

enum GitHubWorkflowPathFilterPolicy {
    static func matches(
        trigger: GitHubWorkflowPushTrigger,
        branch: String,
        changedFiles: [String]
    ) -> Bool {
        if !trigger.branches.isEmpty &&
            !matchesOrderedPatterns(trigger.branches, value: branch) {
            return false
        }

        if trigger.branchesIgnore.contains(where: { matchesPattern($0, value: branch) }) {
            return false
        }

        if !trigger.paths.isEmpty {
            guard changedFiles.contains(where: { matchesOrderedPatterns(trigger.paths, value: $0) }) else {
                return false
            }
        }

        if !trigger.pathsIgnore.isEmpty {
            let allIgnored = changedFiles.allSatisfy { path in
                trigger.pathsIgnore.contains(where: { matchesPattern($0, value: path) })
            }
            if allIgnored {
                return false
            }
        }

        return true
    }

    private static func matchesOrderedPatterns(
        _ patterns: [String],
        value: String
    ) -> Bool {
        var isIncluded = false
        var sawPositive = false

        for pattern in patterns {
            let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPattern.isEmpty else {
                continue
            }

            if normalizedPattern.hasPrefix("!") {
                let candidate = String(normalizedPattern.dropFirst())
                if matchesPattern(candidate, value: value) {
                    isIncluded = false
                }
                continue
            }

            sawPositive = true
            if matchesPattern(normalizedPattern, value: value) {
                isIncluded = true
            }
        }

        return sawPositive ? isIncluded : false
    }

    private static func matchesPattern(
        _ pattern: String,
        value: String
    ) -> Bool {
        let regexPattern = regex(for: pattern)
        return value.range(of: regexPattern, options: .regularExpression) != nil
    }

    private static func regex(for pattern: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let placeholder = "__DOUBLE_STAR__"
        let withDoubleStars = escaped.replacingOccurrences(of: "\\*\\*", with: placeholder)
        let withSingleStars = withDoubleStars.replacingOccurrences(of: "\\*", with: "[^/]*")
        let withQuestionMarks = withSingleStars.replacingOccurrences(of: "\\?", with: "[^/]")
        let restored = withQuestionMarks.replacingOccurrences(of: placeholder, with: ".*")
        return "^\(restored)$"
    }
}

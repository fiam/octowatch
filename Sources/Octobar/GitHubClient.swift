import Foundation

enum GitHubClientError: LocalizedError {
    case invalidResponse
    case invalidCredentials
    case api(statusCode: Int, message: String)
    case rateLimited(GitHubRateLimit?)
    case tokenValidation(message: String)
    case unsupportedRepositoryName(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub API returned an invalid response."
        case .invalidCredentials:
            return "GitHub credentials were rejected."
        case let .api(statusCode, message):
            return "GitHub API error \(statusCode): \(message)"
        case .rateLimited:
            return "GitHub API rate limit exceeded. Octowatch will retry after the reset window."
        case let .tokenValidation(message):
            return message
        case let .unsupportedRepositoryName(name):
            return "Unsupported repository name format: \(name)"
        }
    }
}

struct GitHubClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL = URL(string: "https://api.github.com")!
    private let graphQLURL = URL(string: "https://api.github.com/graphql")!
    private let notificationPageSize = 50
    private let steadyNotificationPageLimit = 2
    private let initialNotificationPageLimit = 5
    private let maximumNotificationPageLimit = 10
    private let actionableNotificationLimit = 64
    private let notificationEnrichmentLimit = 10
    private let authoredPullRequestLimit = 12
    private let trackedPullRequestLimit = 20
    private let trackedIssueLimit = 20
    private let workflowCandidateLimit = 8
    private let workflowRunLimit = 20

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    private static let pullRequestFocusQuery = """
    query PullRequestFocus($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        viewerPermission
        mergeCommitAllowed
        squashMergeAllowed
        rebaseMergeAllowed
        pullRequest(number: $number) {
          id
          title
          bodyHTML
          url
          baseRefName
          state
          merged
          isInMergeQueue
          isDraft
          reviewDecision
          mergeable
          viewerDidAuthor
          headRefOid
          mergeCommit {
            oid
          }
          reviewRequests(first: 20) {
            totalCount
          }
          author {
            __typename
            login
            avatarUrl
            url
          }
          timelineItems(last: 20, itemTypes: [ASSIGNED_EVENT]) {
            nodes {
              __typename
              ... on AssignedEvent {
                createdAt
                actor {
                  __typename
                  login
                  avatarUrl
                  url
                }
                assignee {
                  __typename
                  ... on User {
                    login
                    avatarUrl
                    url
                  }
                  ... on Bot {
                    login
                    avatarUrl
                    url
                  }
                  ... on Mannequin {
                    login
                    avatarUrl
                    url
                  }
                }
              }
            }
          }
          reviewThreads(first: 50) {
            nodes {
              id
              isResolved
              isOutdated
              path
              line
              startLine
              comments(first: 30) {
                nodes {
                  id
                  body
                  createdAt
                  url
                  outdated
                  viewerDidAuthor
                  author {
                    __typename
                    login
                    avatarUrl
                    url
                  }
                }
              }
            }
          }
          reviews(last: 50) {
            nodes {
              state
              submittedAt
              url
              author {
                __typename
                login
                avatarUrl
                url
              }
            }
          }
          commits(last: 20) {
            nodes {
              commit {
                oid
                abbreviatedOid
                messageHeadline
                committedDate
                url
                author {
                  user {
                    __typename
                    login
                    avatarUrl
                    url
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    private static let pullRequestNodeIDQuery = """
    query PullRequestNodeID($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          id
          merged
          isInMergeQueue
        }
      }
    }
    """

    private static let enqueuePullRequestMutation = """
    mutation EnqueuePullRequest($pullRequestId: ID!) {
      enqueuePullRequest(input: { pullRequestId: $pullRequestId }) {
        mergeQueueEntry {
          id
        }
      }
    }
    """

    func validateToken(token: String) async throws -> String {
        let user: CurrentUser = try await request(path: "/user", token: token)

        do {
            let _: [NotificationThread] = try await request(
                path: "/notifications",
                queryItems: [
                    URLQueryItem(name: "all", value: "false"),
                    URLQueryItem(name: "per_page", value: "1")
                ],
                token: token
            )
        } catch {
            throw mapTokenValidationError(
                error,
                fallback: """
                This token cannot access GitHub notifications. Octowatch needs a token \
                that works with the notifications API.
                """
            )
        }

        do {
            let _: SearchIssuesResponse = try await request(
                path: "/search/issues",
                queryItems: [
                    URLQueryItem(
                        name: "q",
                        value: "is:open is:pr assignee:\(user.login) archived:false"
                    ),
                    URLQueryItem(name: "per_page", value: "1")
                ],
                token: token
            )
        } catch {
            throw mapTokenValidationError(
                error,
                fallback: """
                This token cannot search pull requests assigned to you. Octowatch needs \
                access to GitHub search for pull requests.
                """
            )
        }

        return user.login
    }

    func fetchSnapshot(
        token: String,
        preferredLogin: String?,
        notificationScanState: NotificationScanState,
        teamMembershipCache: TeamMembershipCache
    ) async throws -> GitHubSnapshot {
        let observer = GitHubRateLimitObserver()
        let login = try await resolveLogin(
            token: token,
            preferredLogin: preferredLogin,
            observer: observer
        )
        let resolvedTeamMembershipCache = await resolveTeamMembershipCache(
            token: token,
            existingCache: teamMembershipCache,
            observer: observer
        )

        async let pullRequestsTask = fetchAssignedPullRequests(
            token: token,
            login: login,
            observer: observer
        )
        async let trackedPullRequestsTask = fetchTrackedPullRequests(
            token: token,
            login: login,
            observer: observer
        )
        async let readyToMergeTask = fetchReadyToMergePullRequests(
            token: token,
            login: login,
            observer: observer
        )
        async let notificationsTask = fetchActionableNotifications(
            token: token,
            login: login,
            scanState: notificationScanState,
            teamMembershipCache: resolvedTeamMembershipCache,
            observer: observer
        )
        async let workflowRunsTask = fetchWatchedWorkflowRuns(
            token: token,
            login: login,
            observer: observer
        )
        async let trackedIssuesTask = fetchTrackedIssues(
            token: token,
            login: login,
            observer: observer
        )

        let pullRequests = try await pullRequestsTask
        let trackedPullRequests = try await trackedPullRequestsTask
        let readyToMerge = try await readyToMergeTask
        let notificationFetch = try await notificationsTask
        let workflowRuns = try await workflowRunsTask
        let trackedIssues = try await trackedIssuesTask

        let attentionItems = buildAttentionItems(
            pullRequests: pullRequests,
            trackedPullRequests: trackedPullRequests,
            readyToMerge: readyToMerge,
            notifications: notificationFetch.notifications,
            actionRuns: workflowRuns,
            trackedIssues: trackedIssues
        )

        return GitHubSnapshot(
            login: login,
            attentionItems: attentionItems,
            rateLimit: await observer.snapshot(),
            notificationScanState: notificationFetch.scanState,
            teamMembershipCache: resolvedTeamMembershipCache
        )
    }

    private func buildAttentionItems(
        pullRequests: [PullRequestSummary],
        trackedPullRequests: [TrackedSubjectSummary],
        readyToMerge: [ReadyToMergeSummary],
        notifications: [NotificationSummary],
        actionRuns: [ActionRunSummary],
        trackedIssues: [TrackedSubjectSummary]
    ) -> [AttentionItem] {
        let pullRequestItems = pullRequests.map { pullRequest in
            AttentionItem(
                id: pullRequestItemID(
                    prefix: "pr",
                    baseID: "\(pullRequest.id)",
                    resolution: pullRequest.resolution
                ),
                ignoreKey: pullRequest.ignoreKey,
                stream: .pullRequests,
                type: .assignedPullRequest,
                title: pullRequest.title,
                subtitle: pullRequest.subtitle,
                repository: pullRequest.repository,
                timestamp: pullRequest.updatedAt,
                url: pullRequest.url,
                detail: detail(for: pullRequest),
                isHistoricalLogEntry: pullRequest.resolution == .merged,
                isUnread: pullRequest.resolution != .merged
            )
        }

        let readyToMergeItems = readyToMerge.map { pullRequest in
            AttentionItem(
                id: "ready:\(pullRequest.id)",
                ignoreKey: pullRequest.ignoreKey,
                stream: .pullRequests,
                type: .readyToMerge,
                title: pullRequest.title,
                subtitle: pullRequest.subtitle,
                repository: pullRequest.repository,
                timestamp: pullRequest.updatedAt,
                url: pullRequest.url,
                actor: pullRequest.actor,
                detail: detail(for: pullRequest)
            )
        }

        let notificationItems = notifications.map { notification in
            AttentionItem(
                id: "notif:\(notification.id)",
                ignoreKey: notification.ignoreKey,
                stream: .notifications,
                type: notification.type,
                title: notification.title,
                subtitle: notification.subtitle,
                repository: notification.repository,
                timestamp: notification.updatedAt,
                url: notification.url,
                actor: notification.actor,
                detail: detail(for: notification),
                isUnread: notification.unread
            )
        }

        let actionRunItems = actionRuns.map { run in
            AttentionItem(
                id: "run:\(run.id)",
                ignoreKey: run.ignoreKey,
                stream: .pullRequests,
                type: run.type,
                title: run.title,
                subtitle: run.subtitle,
                repository: run.repository,
                timestamp: run.createdAt,
                url: run.url,
                actor: run.actor,
                detail: detail(for: run)
            )
        }

        let directPullRequestKeys = Set((pullRequestItems + readyToMergeItems).map(\.ignoreKey))
        let trackedPullRequestItems = trackedPullRequests
            .filter { !directPullRequestKeys.contains($0.ignoreKey) }
            .map { trackedSubject in
                AttentionItem(
                    id: pullRequestItemID(
                        prefix: "tracked-pr",
                        baseID: trackedSubject.id,
                        resolution: trackedSubject.resolution
                    ),
                    ignoreKey: trackedSubject.ignoreKey,
                    stream: .pullRequests,
                    type: trackedSubject.type,
                    title: trackedSubject.title,
                    subtitle: trackedSubject.subtitle,
                    repository: trackedSubject.repository,
                    timestamp: trackedSubject.updatedAt,
                    url: trackedSubject.url,
                    detail: detail(for: trackedSubject),
                    isHistoricalLogEntry: trackedSubject.resolution == .merged,
                    isUnread: trackedSubject.resolution != .merged
                )
            }

        let trackedIssueItems = trackedIssues.map { trackedSubject in
            AttentionItem(
                id: "tracked-issue:\(trackedSubject.id)",
                ignoreKey: trackedSubject.ignoreKey,
                stream: .issues,
                type: trackedSubject.type,
                title: trackedSubject.title,
                subtitle: trackedSubject.subtitle,
                repository: trackedSubject.repository,
                timestamp: trackedSubject.updatedAt,
                url: trackedSubject.url,
                detail: detail(for: trackedSubject)
            )
        }

        return (
            pullRequestItems +
                trackedPullRequestItems +
                readyToMergeItems +
                notificationItems +
                actionRunItems +
                trackedIssueItems
        )
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func detail(for pullRequest: PullRequestSummary) -> AttentionDetail {
        AttentionDetail(
            contextPillTitle: pullRequest.resolution == .merged ? "Merged" : nil,
            why: AttentionWhy(
                summary: pullRequest.resolution == .merged
                    ? "This merged pull request is kept in your log."
                    : "This pull request is assigned to you directly.",
                detail: pullRequest.resolution == .merged
                    ? "Review the merge result and the workflows it triggered."
                    : "Review it, move it forward, or decide whether to ignore it."
            ),
            evidence: [
                AttentionEvidence(
                    id: "subject",
                    title: "Pull request",
                    detail: "#\(pullRequest.number) · \(pullRequest.title)",
                    iconName: "arrow.triangle.pull",
                    url: pullRequest.url
                ),
                AttentionEvidence(
                    id: "repository",
                    title: "Repository",
                    detail: pullRequest.repository,
                    iconName: "shippingbox",
                    url: repositoryWebURL(repository: pullRequest.repository)
                ),
                AttentionEvidence(
                    id: "status",
                    title: "Current status",
                    detail: "Open and waiting in your inbox.",
                    iconName: "person.crop.circle.badge.checkmark"
                )
            ],
            actions: [
                AttentionAction(
                    id: "open-pr",
                    title: "Open Pull Request",
                    iconName: "arrow.up.right.square",
                    url: pullRequest.url,
                    isPrimary: true
                ),
                AttentionAction(
                    id: "open-repo",
                    title: "Open Repository",
                    iconName: "shippingbox",
                    url: repositoryWebURL(repository: pullRequest.repository)
                )
            ],
            acknowledgement: "Use the toolbar to mark this read or ignore it."
        )
    }

    private func pullRequestItemID(
        prefix: String,
        baseID: String,
        resolution: GitHubSubjectResolution
    ) -> String {
        if resolution == .merged {
            return "\(prefix):\(baseID):merged"
        }

        return "\(prefix):\(baseID)"
    }

    private func detail(for trackedSubject: TrackedSubjectSummary) -> AttentionDetail {
        let isPullRequest = trackedSubject.url.absoluteString.contains("/pull/")
        let subjectTitle = isPullRequest ? "Pull request" : "Issue"
        let subjectIcon = isPullRequest ? "arrow.triangle.pull" : "exclamationmark.circle"

        return AttentionDetail(
            contextPillTitle: trackedSubject.resolution == .merged ? "Merged" : nil,
            why: AttentionWhy(
                summary: trackedSubject.resolution == .merged && isPullRequest
                    ? "This merged pull request is kept in your log."
                    : whySummary(for: trackedSubject.type, actor: nil),
                detail: trackedSubject.subtitle
            ),
            evidence: [
                AttentionEvidence(
                    id: "subject",
                    title: subjectTitle,
                    detail: "#\(trackedSubject.number) · \(trackedSubject.title)",
                    iconName: subjectIcon,
                    url: trackedSubject.url
                ),
                AttentionEvidence(
                    id: "repository",
                    title: "Repository",
                    detail: trackedSubject.repository,
                    iconName: "shippingbox",
                    url: repositoryWebURL(repository: trackedSubject.repository)
                )
            ],
            actions: [
                AttentionAction(
                    id: "open-subject",
                    title: isPullRequest ? "Open Pull Request" : "Open Issue",
                    iconName: "arrow.up.right.square",
                    url: trackedSubject.url,
                    isPrimary: true
                ),
                AttentionAction(
                    id: "open-repo",
                    title: "Open Repository",
                    iconName: "shippingbox",
                    url: repositoryWebURL(repository: trackedSubject.repository)
                )
            ],
            acknowledgement: "Use the toolbar to mark this read or ignore it."
        )
    }

    private func detail(for pullRequest: ReadyToMergeSummary) -> AttentionDetail {
        var evidence = [
            AttentionEvidence(
                id: "subject",
                title: "Pull request",
                detail: "#\(pullRequest.number) · \(pullRequest.title)",
                iconName: "checkmark.circle",
                url: pullRequest.url
            ),
            AttentionEvidence(
                id: "repository",
                title: "Repository",
                detail: pullRequest.repository,
                iconName: "shippingbox",
                url: repositoryWebURL(repository: pullRequest.repository)
            ),
            AttentionEvidence(
                id: "approvals",
                title: "Current approvals",
                detail: "\(pullRequest.approvalCount) approval\(pullRequest.approvalCount == 1 ? "" : "s")",
                iconName: "person.badge.shield.checkmark"
            )
        ]

        if let actor = pullRequest.actor {
            evidence.append(
                AttentionEvidence(
                    id: "actor",
                    title: "Latest approver",
                    detail: actor.login,
                    iconName: "person.crop.circle.badge.checkmark",
                    url: actor.isBotAccount ? nil : actor.profileURL
                )
            )
        }

        var actions = [
            AttentionAction(
                id: "open-pr",
                title: "Open Pull Request",
                iconName: "arrow.up.right.square",
                url: pullRequest.url,
                isPrimary: true
            )
        ]

        if let actor = pullRequest.actor, !actor.isBotAccount {
            actions.append(
                AttentionAction(
                    id: "open-actor",
                    title: "Open \(actor.login)",
                    iconName: "person.crop.circle",
                    url: actor.profileURL
                )
            )
        }

        return AttentionDetail(
            why: AttentionWhy(
                summary: "This pull request is approved and looks ready to merge.",
                detail: "There are no pending review requests and GitHub reports a clean merge state."
            ),
            evidence: evidence,
            actions: actions,
            acknowledgement: "Use the toolbar to mark this read or ignore it."
        )
    }

    private func detail(for notification: NotificationSummary) -> AttentionDetail {
        var evidence = [
            AttentionEvidence(
                id: "repository",
                title: "Repository",
                detail: notification.repository,
                iconName: "shippingbox",
                url: repositoryWebURL(repository: notification.repository)
            )
        ]

        if let targetLabel = notification.targetLabel {
            evidence.append(
                AttentionEvidence(
                    id: "target",
                    title: "Why this surfaced",
                    detail: targetLabel,
                    iconName: notification.type == .teamReviewRequested || notification.type == .teamMention
                        ? "person.2"
                        : "person"
                    )
            )
        }

        evidence.append(contentsOf: notification.detailEvidence)

        if let actor = notification.actor {
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
                id: "open-subject",
                title: openActionTitle(for: notification.url),
                iconName: "arrow.up.right.square",
                url: notification.url,
                isPrimary: true
            )
        ]

        if let actor = notification.actor, !actor.isBotAccount {
            actions.append(
                AttentionAction(
                    id: "open-actor",
                    title: "Open \(actor.login)",
                    iconName: "person.crop.circle",
                    url: actor.profileURL
                )
            )
        }

        return AttentionDetail(
            contextPillTitle: notification.stateTransition?.title,
            why: AttentionWhy(
                summary: whySummary(
                    for: notification.type,
                    actor: notification.actor,
                    stateTransition: notification.stateTransition
                ),
                detail: notification.targetLabel
            ),
            evidence: evidence,
            actions: actions,
            acknowledgement: "Use the toolbar to mark this read or ignore it."
        )
    }

    private func detail(for run: ActionRunSummary) -> AttentionDetail {
        let pullRequestURL = URL(string: run.ignoreKey)

        var evidence = [
            AttentionEvidence(
                id: "run",
                title: "Workflow run",
                detail: run.title,
                iconName: run.type.iconName,
                url: run.url
            ),
            AttentionEvidence(
                id: "repository",
                title: "Repository",
                detail: run.repository,
                iconName: "shippingbox",
                url: repositoryWebURL(repository: run.repository)
            )
        ]

        if let pullRequestURL {
            evidence.append(
                AttentionEvidence(
                    id: "subject",
                    title: "Related pull request",
                    detail: subjectLabel(for: pullRequestURL),
                    iconName: "arrow.triangle.pull",
                    url: pullRequestURL
                )
            )
        }

        if let actor = run.actor {
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
                id: "open-run",
                title: "Open Workflow Run",
                iconName: "bolt",
                url: run.url,
                isPrimary: true
            )
        ]

        if let pullRequestURL {
            actions.append(
                AttentionAction(
                    id: "open-pr",
                    title: "Open Pull Request",
                    iconName: "arrow.triangle.pull",
                    url: pullRequestURL
                )
            )
        }

        return AttentionDetail(
            why: AttentionWhy(
                summary: whySummary(for: run.type, actor: run.actor),
                detail: "This workflow activity was attached to a pull request Octowatch is already watching."
            ),
            evidence: evidence,
            actions: actions,
            acknowledgement: "Use the toolbar to mark this read or ignore it."
        )
    }

    func fetchPullRequestFocus(
        token: String,
        login: String,
        reference: PullRequestReference,
        sourceType: AttentionItemType
    ) async throws -> PullRequestFocusResult {
        let observer = GitHubRateLimitObserver()
        let response: PullRequestFocusQueryData = try await graphQLRequest(
            query: Self.pullRequestFocusQuery,
            variables: PullRequestFocusQueryVariables(
                owner: reference.owner,
                name: reference.name,
                number: reference.number
            ),
            token: token,
            observer: observer
        )

        guard let pullRequest = response.repository?.pullRequest else {
            throw GitHubClientError.invalidResponse
        }

        let reviews = pullRequest.reviews.nodes.compactMap { $0 }
        let threads = pullRequest.reviewThreads.nodes.compactMap { $0 }
        let commits = pullRequest.commits.nodes.compactMap { $0?.commit }
        let author = attentionActor(from: pullRequest.author)
        let approvalSummary = latestApprovalSummary(
            reviews: reviews,
            excluding: login
        )
        let pendingReviewRequestCount = pullRequest.reviewRequests.totalCount
        let latestAssignment = pullRequest.timelineItems.nodes
            .compactMap { $0 }
            .filter {
                guard let assignee = $0.assignee?.login else {
                    return false
                }

                return assignee.caseInsensitiveCompare(login) == .orderedSame
            }
            .max { $0.createdAt < $1.createdAt }
        let assigner = attentionActor(from: latestAssignment?.actor)
        let headerFacts = PullRequestHeaderFact.build(
            sourceType: sourceType,
            author: author,
            assigner: assigner,
            latestApprover: approvalSummary.latestApprover,
            approvalCount: approvalSummary.approvalCount
        )
        let contextBadges = PullRequestContextBadge.badges(
            for: sourceType,
            author: author
        )
        let latestViewerReview = reviews
            .filter {
                guard let reviewer = $0.author?.login else {
                    return false
                }

                return reviewer.caseInsensitiveCompare(login) == .orderedSame &&
                    $0.state.caseInsensitiveCompare("PENDING") != .orderedSame
            }
            .max { $0.submittedAt < $1.submittedAt }

        let participatedThreads = threads.filter { thread in
            thread.comments.nodes.compactMap { $0 }.contains(where: \.viewerDidAuthor)
        }
        let focusMode: PullRequestFocusMode
        if pullRequest.viewerDidAuthor {
            focusMode = .authored
        } else if latestViewerReview != nil || !participatedThreads.isEmpty {
            focusMode = .participating
        } else {
            focusMode = .generic
        }

        let relevantThreads: [PullRequestFocusThread]
        switch focusMode {
        case .authored, .generic:
            relevantThreads = threads.compactMap(pullRequestFocusThread(from:))
        case .participating:
            relevantThreads = participatedThreads.compactMap(pullRequestFocusThread(from:))
        }

        let openThreads = relevantThreads.filter { !$0.isResolved && !$0.isOutdated }
        let outdatedThreads = relevantThreads.filter { !$0.isResolved && $0.isOutdated }
        let checkInsights = try await fetchCheckInsights(
            token: token,
            reference: reference,
            headSHA: pullRequest.headRefOID,
            observer: observer
        )
        let postMergeWorkflowPreview = try? await fetchPostMergeWorkflowPreview(
            token: token,
            reference: reference,
            branch: pullRequest.baseRefName,
            mergeCommitSHA: pullRequest.mergeCommit?.oid,
            observer: observer
        )
        let commitsSinceReview: [PullRequestFocusEntry]
        if let latestViewerReview {
            commitsSinceReview = focusCommitEntries(
                from: commits.filter { $0.committedDate > latestViewerReview.submittedAt }
            )
        } else {
            commitsSinceReview = []
        }

        let sections = buildPullRequestFocusSections(
            mode: focusMode,
            openThreads: openThreads,
            outdatedThreads: outdatedThreads,
            commitsSinceReview: commitsSinceReview,
            failedChecks: checkInsights.failingEntries
        )
        let openThreadCount = openThreads.count + outdatedThreads.count
        let reviewMergeAction = PullRequestReviewMergeAction.makeAction(
            sourceType: sourceType,
            mode: focusMode,
            author: author,
            viewerPermission: response.repository?.viewerPermission,
            allowMergeCommit: response.repository?.mergeCommitAllowed ?? false,
            allowSquashMerge: response.repository?.squashMergeAllowed ?? false,
            allowRebaseMerge: response.repository?.rebaseMergeAllowed ?? false,
            mergeable: pullRequest.mergeable,
            isDraft: pullRequest.isDraft,
            reviewDecision: pullRequest.reviewDecision,
            approvalCount: approvalSummary.approvalCount,
            hasChangesRequested: approvalSummary.hasChangesRequested,
            pendingReviewRequestCount: pendingReviewRequestCount,
            checkSummary: checkInsights.summary,
            openThreadCount: openThreadCount,
            isMerged: pullRequest.merged,
            isInMergeQueue: pullRequest.isInMergeQueue
        )
        let statusSummary = PullRequestStatusSummary.build(
            mode: focusMode,
            resolution: pullRequest.merged ? .merged
                : (pullRequest.state.caseInsensitiveCompare("closed") == .orderedSame ? .closed : .open),
            checkSummary: checkInsights.summary,
            openThreadCount: openThreadCount,
            reviewMergeAction: reviewMergeAction
        )
        let actions = AttentionAction.pullRequestActions(
            reference: reference,
            mode: focusMode,
            checkSummary: checkInsights.summary,
            hasNewCommits: !commitsSinceReview.isEmpty,
            hasPrimaryMutationAction: reviewMergeAction?.isEnabled == true
        )

        let focus = PullRequestFocus(
            reference: reference,
            sourceType: sourceType,
            mode: focusMode,
            resolution: pullRequest.merged ? .merged
                : (pullRequest.state.caseInsensitiveCompare("closed") == .orderedSame ? .closed : .open),
            author: author,
            headerFacts: headerFacts,
            contextBadges: contextBadges,
            descriptionHTML: renderedPullRequestDescriptionHTML(pullRequest.bodyHTML),
            statusSummary: statusSummary,
            postMergeWorkflowPreview: postMergeWorkflowPreview,
            sections: sections,
            actions: actions,
            reviewMergeAction: reviewMergeAction,
            emptyStateTitle: focusEmptyStateTitle(
                for: focusMode,
                reviewMergeAction: reviewMergeAction
            ),
            emptyStateDetail: focusEmptyStateDetail(
                for: focusMode,
                reviewMergeAction: reviewMergeAction
            )
        )

        return PullRequestFocusResult(
            focus: focus,
            rateLimit: await observer.snapshot()
        )
    }

    func approveAndMergePullRequest(
        token: String,
        reference: PullRequestReference,
        approveFirst: Bool,
        preferredMergeMethod: PullRequestMergeMethod?
    ) async throws -> PullRequestMutationResult {
        let observer = GitHubRateLimitObserver()

        if approveFirst {
            let _: PullRequestReviewSubmissionResponse = try await request(
                method: "POST",
                path: "/repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)/reviews",
                body: PullRequestReviewSubmissionRequest(event: "APPROVE"),
                token: token,
                observer: observer
            )
        }

        let repositoryMergeSettings: RepositoryMergeSettingsResponse = try await request(
            path: "/repos/\(reference.owner)/\(reference.name)",
            token: token,
            observer: observer
        )
        let mergeMethod = preferredMergeMethod ?? PullRequestMergeMethod.preferred(
            allowMergeCommit: repositoryMergeSettings.allowMergeCommit,
            allowSquashMerge: repositoryMergeSettings.allowSquashMerge,
            allowRebaseMerge: repositoryMergeSettings.allowRebaseMerge
        )

        guard let mergeMethod else {
            throw GitHubClientError.api(
                statusCode: 405,
                message: "This repository does not allow pull requests to be merged directly."
            )
        }

        let mergeResponse: PullRequestMergeResponse
        do {
            mergeResponse = try await request(
                method: "PUT",
                path: "/repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)/merge",
                body: PullRequestMergeRequest(mergeMethod: mergeMethod.rawValue),
                token: token,
                observer: observer
            )
        } catch let GitHubClientError.api(statusCode, message)
            where shouldUseMergeQueueFallback(statusCode: statusCode, message: message) {
            let pullRequestID = try await fetchPullRequestNodeID(
                token: token,
                reference: reference
            )
            let _: EnqueuePullRequestMutationData = try await graphQLRequest(
                query: Self.enqueuePullRequestMutation,
                variables: EnqueuePullRequestMutationVariables(pullRequestID: pullRequestID),
                token: token,
                observer: observer
            )

            return PullRequestMutationResult(
                outcome: .queued,
                rateLimit: await observer.snapshot()
            )
        }

        if !mergeResponse.merged {
            throw GitHubClientError.api(statusCode: 200, message: mergeResponse.message)
        }

        return PullRequestMutationResult(
            outcome: .merged,
            rateLimit: await observer.snapshot()
        )
    }

    func fetchSubjectResolutionState(
        token: String,
        reference: GitHubSubjectReference,
        login: String?
    ) async throws -> GitHubSubjectResolutionState {
        let observer = GitHubRateLimitObserver()

        switch reference.kind {
        case .pullRequest:
            let response: PullRequestStateResponse = try await request(
                path: "/repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)",
                token: token,
                observer: observer
            )

            let resolution: GitHubSubjectResolution
            if response.merged {
                resolution = .merged
            } else if response.state.caseInsensitiveCompare("closed") == .orderedSame {
                resolution = .closed
            } else {
                resolution = .open
            }

            let isAssignedToViewer: Bool?
            if let login {
                isAssignedToViewer = (response.assignees ?? []).contains {
                    $0.login.caseInsensitiveCompare(login) == .orderedSame
                }
            } else {
                isAssignedToViewer = nil
            }

            return GitHubSubjectResolutionState(
                reference: reference,
                resolution: resolution,
                isAssignedToViewer: isAssignedToViewer,
                mergedAt: response.mergedAt,
                mergeCommitSHA: response.mergeCommitSHA
            )

        case .issue:
            let response: IssueStateResponse = try await request(
                path: "/repos/\(reference.owner)/\(reference.name)/issues/\(reference.number)",
                token: token,
                observer: observer
            )

            return GitHubSubjectResolutionState(
                reference: reference,
                resolution: response.state.caseInsensitiveCompare("closed") == .orderedSame
                    ? .closed
                    : .open,
                isAssignedToViewer: nil,
                mergedAt: nil,
                mergeCommitSHA: nil
            )
        }
    }

    func fetchPostMergeWatchObservation(
        token: String,
        watch: PostMergeWatch
    ) async throws -> PostMergeWatchObservationResult {
        let observer = GitHubRateLimitObserver()
        let details: PullRequestDetails = try await request(
            path: "/repos/\(watch.reference.owner)/\(watch.reference.name)/pulls/\(watch.reference.number)",
            token: token,
            observer: observer
        )

        let resolution: GitHubSubjectResolution
        if details.merged {
            resolution = .merged
        } else if details.state.caseInsensitiveCompare("closed") == .orderedSame {
            resolution = .closed
        } else {
            resolution = .open
        }

        let workflowRuns: [PostMergeObservedWorkflowRun]
        if details.merged, let mergeCommitSHA = details.mergeCommitSHA {
            let runs = try await fetchWorkflowRunsForCommit(
                token: token,
                repository: watch.repository,
                commitSHA: mergeCommitSHA,
                observer: observer
            )
            workflowRuns = postMergeObservedWorkflowRuns(
                from: runs,
                repository: watch.repository
            )
        } else {
            workflowRuns = []
        }

        return PostMergeWatchObservationResult(
            observation: PostMergeWatchObservation(
                resolution: resolution,
                mergedAt: details.mergedAt,
                mergeCommitSHA: details.mergeCommitSHA,
                workflowRuns: workflowRuns
            ),
            rateLimit: await observer.snapshot()
        )
    }

    func fetchPullRequestLiveWatchUpdate(
        token: String,
        reference: PullRequestReference,
        previous: PullRequestLiveWatchState?
    ) async throws -> PullRequestLiveWatchUpdateResult {
        let observer = GitHubRateLimitObserver()

        let detailsResponse: ConditionalRequestResult<PullRequestDetails> = try await conditionalRequest(
            path: "/repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)",
            ifNoneMatch: previous?.detailsETag,
            token: token,
            observer: observer
        )

        let timelineResponse: ConditionalRequestResult<[TimelineEntry]> = try await conditionalRequest(
            path: "/repos/\(reference.owner)/\(reference.name)/issues/\(reference.number)/timeline",
            queryItems: [
                URLQueryItem(name: "per_page", value: "1")
            ],
            ifNoneMatch: previous?.timelineETag,
            token: token,
            observer: observer
        )

        let resolution: GitHubSubjectResolution
        let isInMergeQueue: Bool
        let headSHA: String?
        let detailsETag: String?
        switch detailsResponse {
        case let .modified(value, etag):
            resolution = subjectResolution(for: value)
            isInMergeQueue = false
            headSHA = value.head.sha
            detailsETag = etag
        case let .notModified(etag):
            guard let previous else {
                throw GitHubClientError.invalidResponse
            }
            resolution = previous.resolution
            isInMergeQueue = previous.isInMergeQueue
            headSHA = previous.headSHA
            detailsETag = etag ?? previous.detailsETag
        }

        let timelineETag: String?
        let latestTimelineMarker: String?
        switch timelineResponse {
        case let .modified(value, etag):
            timelineETag = etag
            if let entry = value.last ?? value.first {
                if let id = entry.id {
                    latestTimelineMarker = "\(id)"
                } else if let createdAt = entry.createdAt ?? entry.submittedAt {
                    latestTimelineMarker = "\(createdAt.timeIntervalSince1970)"
                } else {
                    latestTimelineMarker = etag
                }
            } else {
                latestTimelineMarker = etag
            }
        case let .notModified(etag):
            timelineETag = etag ?? previous?.timelineETag
            latestTimelineMarker = previous?.latestTimelineMarker
        }

        let state = PullRequestLiveWatchState(
            reference: reference,
            resolution: resolution,
            isInMergeQueue: resolution == .merged ? false : isInMergeQueue,
            headSHA: headSHA?.isEmpty == true ? previous?.headSHA : headSHA,
            latestTimelineMarker: latestTimelineMarker,
            detailsETag: detailsETag ?? previous?.detailsETag,
            timelineETag: timelineETag ?? previous?.timelineETag
        )

        return PullRequestLiveWatchUpdateResult(
            update: PullRequestLiveWatchPolicy.apply(previous: previous, current: state),
            rateLimit: await observer.snapshot()
        )
    }

    private func fetchPullRequestNodeID(
        token: String,
        reference: PullRequestReference
    ) async throws -> String {
        let response: PullRequestNodeIDQueryData = try await graphQLRequest(
            query: Self.pullRequestNodeIDQuery,
            variables: PullRequestFocusQueryVariables(
                owner: reference.owner,
                name: reference.name,
                number: reference.number
            ),
            token: token
        )

        guard let pullRequestID = response.repository?.pullRequest?.id else {
            throw GitHubClientError.invalidResponse
        }

        return pullRequestID
    }

    private func shouldUseMergeQueueFallback(statusCode: Int, message: String) -> Bool {
        GitHubMergeQueuePolicy.shouldFallback(statusCode: statusCode, message: message)
    }

    private func subjectResolution(for details: PullRequestDetails) -> GitHubSubjectResolution {
        if details.merged {
            return .merged
        }

        if details.state.caseInsensitiveCompare("closed") == .orderedSame {
            return .closed
        }

        return .open
    }

    private func resolveLogin(
        token: String,
        preferredLogin: String?,
        observer: GitHubRateLimitObserver
    ) async throws -> String {
        if let preferredLogin, !preferredLogin.isEmpty {
            return preferredLogin
        }

        let user: CurrentUser = try await request(
            path: "/user",
            token: token,
            observer: observer
        )
        return user.login
    }

    private func resolveTeamMembershipCache(
        token: String,
        existingCache: TeamMembershipCache,
        observer: GitHubRateLimitObserver
    ) async -> TeamMembershipCache {
        let normalizedCache = existingCache.normalized
        guard !normalizedCache.isFresh() else {
            return normalizedCache
        }

        do {
            let teams = try await fetchCurrentUserTeams(
                token: token,
                observer: observer
            )
            let membershipKeys: [String] = teams.compactMap { team -> String? in
                guard let owner = team.organization?.login, !owner.isEmpty else {
                    return nil
                }

                return TeamMembershipCache.membershipKey(owner: owner, slug: team.slug)
            }
            return normalizedCache.refreshed(membershipKeys: membershipKeys)
        } catch {
            return normalizedCache.recordingAttempt()
        }
    }

    private func fetchCurrentUserTeams(
        token: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [GitHubTeam] {
        var teams: [GitHubTeam] = []

        for page in 1...10 {
            let pageTeams: [GitHubTeam] = try await request(
                path: "/user/teams",
                queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ],
                token: token,
                observer: observer
            )
            teams.append(contentsOf: pageTeams)

            if pageTeams.count < 100 {
                break
            }
        }

        return teams
    }

    private func buildPullRequestFocusSections(
        mode: PullRequestFocusMode,
        openThreads: [PullRequestFocusThread],
        outdatedThreads: [PullRequestFocusThread],
        commitsSinceReview: [PullRequestFocusEntry],
        failedChecks: [PullRequestFocusEntry]
    ) -> [PullRequestFocusSection] {
        var sections = [PullRequestFocusSection]()
        let sortedOpenThreads = openThreads.sorted { $0.latestActivityAt > $1.latestActivityAt }
        let sortedOutdatedThreads = outdatedThreads.sorted { $0.latestActivityAt > $1.latestActivityAt }

        if !sortedOpenThreads.isEmpty {
            sections.append(
                PullRequestFocusSection(
                    id: "open-threads",
                    title: mode == .participating ? "Your Open Conversations" : "Open Conversations",
                    items: sortedOpenThreads.map(\.entry)
                )
            )
        }

        if !sortedOutdatedThreads.isEmpty {
            sections.append(
                PullRequestFocusSection(
                    id: "outdated-threads",
                    title: mode == .participating ? "Your Outdated Conversations" : "Outdated Conversations",
                    items: sortedOutdatedThreads.map(\.entry)
                )
            )
        }

        if !commitsSinceReview.isEmpty {
            sections.append(
                PullRequestFocusSection(
                    id: "changes-since-review",
                    title: "Changes Since Your Review",
                    items: commitsSinceReview
                )
            )
        }

        if !failedChecks.isEmpty {
            sections.append(
                PullRequestFocusSection(
                    id: "failed-checks",
                    title: "Failing Checks",
                    items: failedChecks
                )
            )
        }

        return sections
    }

    private func focusEmptyStateTitle(
        for mode: PullRequestFocusMode,
        reviewMergeAction: PullRequestReviewMergeAction?
    ) -> String {
        if let reviewMergeAction, reviewMergeAction.isEnabled {
            return reviewMergeAction.requiresApproval
                ? "Ready to approve and merge"
                : "Ready to merge"
        }

        switch mode {
        case .authored:
            return "Ready to merge"
        case .participating:
            return "No follow-up required right now"
        case .generic:
            return "No additional pull request signals"
        }
    }

    private func focusEmptyStateDetail(
        for mode: PullRequestFocusMode,
        reviewMergeAction: PullRequestReviewMergeAction?
    ) -> String {
        if let reviewMergeAction, reviewMergeAction.isEnabled {
            return reviewMergeAction.requiresApproval
                ? "This bot PR is assigned to you, with no unresolved conversations or failing checks."
                : "There are no unresolved conversations or failing checks."
        }

        switch mode {
        case .authored:
            return "There are no unresolved conversations or failing checks."
        case .participating:
            return "There are no open threads from you and no newer commits after your review."
        case .generic:
            return "Octowatch could not find any stronger PR-specific focus items here yet."
        }
    }

    private func pullRequestFocusThread(
        from thread: PullRequestFocusGraphQLReviewThread
    ) -> PullRequestFocusThread? {
        let comments = thread.comments.nodes.compactMap { $0 }
        let latestComment = comments.max { $0.createdAt < $1.createdAt }
        let locationTitle: String
        if let path = thread.path {
            if let line = thread.line ?? thread.startLine {
                locationTitle = "\(path):\(line)"
            } else {
                locationTitle = path
            }
        } else {
            locationTitle = "Conversation"
        }

        let entry = PullRequestFocusEntry(
            id: thread.id,
            title: locationTitle,
            detail: latestComment.map { excerpt($0.body) } ?? "Thread is still unresolved.",
            metadata: latestComment?.author?.login,
            timestamp: latestComment?.createdAt,
            iconName: thread.isOutdated ? "clock.arrow.trianglehead.counterclockwise.rotate.90" : "bubble.left.and.text.bubble.right",
            accent: thread.isOutdated ? .warning : .neutral,
            url: latestComment?.url
        )

        return PullRequestFocusThread(
            isResolved: thread.isResolved,
            isOutdated: thread.isOutdated,
            latestActivityAt: latestComment?.createdAt ?? .distantPast,
            entry: entry
        )
    }

    private func focusCommitEntries(
        from commits: [PullRequestFocusGraphQLCommit]
    ) -> [PullRequestFocusEntry] {
        commits
            .sorted { $0.committedDate > $1.committedDate }
            .map { commit in
                PullRequestFocusEntry(
                    id: "commit-\(commit.oid)",
                    title: commit.messageHeadline,
                    detail: commit.abbreviatedOID,
                    metadata: commit.author?.user?.login,
                    timestamp: commit.committedDate,
                    iconName: "arrow.trianglehead.branch",
                    accent: .change,
                    url: commit.url
                )
            }
    }

    private func fetchCheckInsights(
        token: String,
        reference: PullRequestReference,
        headSHA: String,
        observer: GitHubRateLimitObserver
    ) async throws -> PullRequestCheckInsights {
        let response: CheckRunsResponse = try await request(
            path: "/repos/\(reference.owner)/\(reference.name)/commits/\(headSHA)/check-runs",
            queryItems: [
                URLQueryItem(name: "per_page", value: "100")
            ],
            token: token,
            observer: observer
        )

        let failingConclusions: Set<String> = [
            "action_required",
            "cancelled",
            "failure",
            "startup_failure",
            "timed_out"
        ]
        let pendingStatuses: Set<String> = [
            "queued",
            "in_progress",
            "waiting",
            "pending",
            "requested"
        ]

        var passedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var pendingCount = 0

        let failingEntries = response.checkRuns
            .filter { run in
                let normalizedStatus = run.status.lowercased()
                let normalizedConclusion = run.conclusion?.lowercased()

                if pendingStatuses.contains(normalizedStatus) {
                    pendingCount += 1
                    return false
                }

                switch normalizedConclusion {
                case "success":
                    passedCount += 1
                    return false
                case "skipped", "neutral":
                    skippedCount += 1
                    return false
                case let conclusion? where failingConclusions.contains(conclusion):
                    failedCount += 1
                    return true
                default:
                    if normalizedConclusion == nil {
                        pendingCount += 1
                    }
                    return false
                }
            }
            .sorted {
                ($0.completedAt ?? $0.startedAt ?? .distantPast) >
                    ($1.completedAt ?? $1.startedAt ?? .distantPast)
            }
            .map { run in
                PullRequestFocusEntry(
                    id: "check-\(run.id)",
                    title: run.name,
                    detail: run.conclusion?
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized,
                    metadata: run.app?.slug,
                    timestamp: run.completedAt ?? run.startedAt,
                    iconName: "xmark.octagon",
                    accent: .failure,
                    url: run.htmlURL ?? run.detailsURL
                )
            }

        return PullRequestCheckInsights(
            summary: PullRequestCheckSummary(
                passedCount: passedCount,
                skippedCount: skippedCount,
                failedCount: failedCount,
                pendingCount: pendingCount
            ),
            failingEntries: failingEntries
        )
    }

    private func renderedPullRequestDescriptionHTML(_ html: String) -> String? {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func excerpt(_ body: String) -> String {
        let collapsed = body
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 140 else {
            return collapsed
        }

        return String(collapsed.prefix(137)) + "..."
    }

    private func fetchAssignedPullRequests(
        token: String,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [PullRequestSummary] {
        async let openTask = searchPullRequests(
            token: token,
            query: "is:open is:pr assignee:\(login) archived:false",
            perPage: 20,
            observer: observer
        )
        async let mergedTask = searchPullRequests(
            token: token,
            query: "is:merged is:pr assignee:\(login) archived:false",
            perPage: 20,
            observer: observer
        )

        let open = try await openTask
        let merged = try await mergedTask
        let summaries = open + merged
        var byKey = [String: PullRequestSummary]()

        for summary in summaries {
            if let existing = byKey[summary.ignoreKey], existing.updatedAt >= summary.updatedAt {
                continue
            }

            byKey[summary.ignoreKey] = summary
        }

        return byKey.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func fetchTrackedPullRequests(
        token: String,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [TrackedSubjectSummary] {
        async let authoredTask = searchTrackedSubjects(
            token: token,
            queries: [
                "is:open is:pr author:\(login) archived:false",
                "is:merged is:pr author:\(login) archived:false"
            ],
            type: .authoredPullRequest,
            perPage: trackedPullRequestLimit,
            observer: observer
        )
        async let reviewedTask = searchTrackedSubjects(
            token: token,
            queries: [
                "is:open is:pr reviewed-by:\(login) archived:false",
                "is:merged is:pr reviewed-by:\(login) archived:false"
            ],
            type: .reviewedPullRequest,
            perPage: trackedPullRequestLimit,
            observer: observer
        )
        async let commentedTask = searchTrackedSubjects(
            token: token,
            queries: [
                "is:open is:pr commenter:\(login) archived:false",
                "is:merged is:pr commenter:\(login) archived:false"
            ],
            type: .commentedPullRequest,
            perPage: trackedPullRequestLimit,
            observer: observer
        )

        let authored = try await authoredTask
        let reviewed = try await reviewedTask
        let commented = try await commentedTask

        return mergeTrackedSubjects(authored + reviewed + commented)
    }

    private func fetchTrackedIssues(
        token: String,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [TrackedSubjectSummary] {
        async let assignedTask = searchTrackedSubjects(
            token: token,
            queries: ["is:open is:issue assignee:\(login) archived:false"],
            type: .assignedIssue,
            perPage: trackedIssueLimit,
            observer: observer
        )
        async let authoredTask = searchTrackedSubjects(
            token: token,
            queries: ["is:open is:issue author:\(login) archived:false"],
            type: .authoredIssue,
            perPage: trackedIssueLimit,
            observer: observer
        )
        async let commentedTask = searchTrackedSubjects(
            token: token,
            queries: ["is:open is:issue commenter:\(login) archived:false"],
            type: .commentedIssue,
            perPage: trackedIssueLimit,
            observer: observer
        )

        let assigned = try await assignedTask
        let authored = try await authoredTask
        let commented = try await commentedTask

        return mergeTrackedSubjects(assigned + authored + commented)
    }

    private func searchTrackedSubjects(
        token: String,
        queries: [String],
        type: AttentionItemType,
        perPage: Int,
        observer: GitHubRateLimitObserver
    ) async throws -> [TrackedSubjectSummary] {
        var summaries = [TrackedSubjectSummary]()

        for query in queries {
            let response: SearchIssuesResponse = try await request(
                path: "/search/issues",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "sort", value: "updated"),
                    URLQueryItem(name: "order", value: "desc"),
                    URLQueryItem(name: "per_page", value: "\(perPage)")
                ],
                token: token,
                observer: observer
            )

            let resolution: GitHubSubjectResolution = query.contains("is:merged") ? .merged : .open
            summaries.append(
                contentsOf: response.items.compactMap { issue in
                    guard let repository = repositoryFullName(from: issue.repositoryURL) else {
                        return nil
                    }

                    return TrackedSubjectSummary(
                        id: "\(repository)#\(issue.number)",
                        ignoreKey: issue.htmlURL.absoluteString,
                        type: type,
                        number: issue.number,
                        title: issue.title,
                        subtitle: trackedSubjectSubtitle(for: type, repository: repository),
                        repository: repository,
                        url: issue.htmlURL,
                        updatedAt: issue.updatedAt,
                        resolution: resolution
                    )
                }
            )
        }

        var byKey = [String: TrackedSubjectSummary]()
        for summary in summaries {
            if let existing = byKey[summary.ignoreKey], existing.updatedAt >= summary.updatedAt {
                continue
            }

            byKey[summary.ignoreKey] = summary
        }

        return Array(byKey.values)
    }

    private func searchPullRequests(
        token: String,
        query: String,
        perPage: Int,
        observer: GitHubRateLimitObserver
    ) async throws -> [PullRequestSummary] {
        let response: SearchIssuesResponse = try await request(
            path: "/search/issues",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "per_page", value: "\(perPage)")
            ],
            token: token,
            observer: observer
        )

        let resolution: GitHubSubjectResolution = query.contains("is:merged") ? .merged : .open
        return response.items.compactMap { issue in
            guard let repository = repositoryFullName(from: issue.repositoryURL) else {
                return nil
            }

            return PullRequestSummary(
                id: issue.id,
                ignoreKey: issue.htmlURL.absoluteString,
                number: issue.number,
                title: issue.title,
                subtitle: "#\(issue.number) · \(repository)",
                repository: repository,
                url: issue.htmlURL,
                updatedAt: issue.updatedAt,
                resolution: resolution
            )
        }
    }

    private func mergeTrackedSubjects(_ subjects: [TrackedSubjectSummary]) -> [TrackedSubjectSummary] {
        var byKey = [String: TrackedSubjectSummary]()

        for subject in subjects {
            if let existing = byKey[subject.ignoreKey],
                !TrackedSubjectAttentionPolicy.shouldReplace(existing: existing.type, with: subject.type) {
                continue
            }

            byKey[subject.ignoreKey] = subject
        }

        return byKey.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func trackedSubjectSubtitle(for type: AttentionItemType, repository: String) -> String {
        switch type {
        case .authoredPullRequest, .authoredIssue:
            return "\(repository) · Created by you"
        case .reviewedPullRequest:
            return "\(repository) · Reviewed by you"
        case .commentedPullRequest, .commentedIssue:
            return "\(repository) · Commented on by you"
        case .assignedIssue:
            return "\(repository) · Assigned to you"
        default:
            return repository
        }
    }

    private func fetchReadyToMergePullRequests(
        token: String,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [ReadyToMergeSummary] {
        let response: SearchIssuesResponse = try await request(
            path: "/search/issues",
            queryItems: [
                URLQueryItem(name: "q", value: "is:open is:pr author:\(login) archived:false"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "per_page", value: "\(authoredPullRequestLimit)")
            ],
            token: token,
            observer: observer
        )

        return await withTaskGroup(of: ReadyToMergeSummary?.self) { group in
            for issue in response.items {
                group.addTask {
                    do {
                        return try await buildReadyToMergeSummary(
                            token: token,
                            login: login,
                            issue: issue,
                            observer: observer
                        )
                    } catch {
                        return nil
                    }
                }
            }

            var summaries = [ReadyToMergeSummary]()
            for await summary in group {
                if let summary {
                    summaries.append(summary)
                }
            }

            return summaries.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func buildReadyToMergeSummary(
        token: String,
        login: String,
        issue: IssueItem,
        observer: GitHubRateLimitObserver
    ) async throws -> ReadyToMergeSummary? {
        guard let repository = repositoryFullName(from: issue.repositoryURL) else {
            return nil
        }

        let repositoryID = try parseRepositoryFullName(repository)
        let details: PullRequestDetails = try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/pulls/\(issue.number)",
            token: token,
            observer: observer
        )

        let reviews = try await fetchPullRequestReviews(
            token: token,
            repository: repository,
            number: issue.number,
            observer: observer
        )
        let approvalSummary = latestApprovalSummary(reviews: reviews, excluding: login)

        let pendingReviewRequests = details.requestedReviewers.count + details.requestedTeams.count
        guard AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
            state: details.state,
            merged: details.merged,
            isDraft: details.isDraft,
            mergeable: details.mergeable,
            mergeableState: details.mergeableState,
            pendingReviewRequests: pendingReviewRequests,
            approvalCount: approvalSummary.approvalCount,
            hasChangesRequested: approvalSummary.hasChangesRequested
        ) else {
            return nil
        }

        let subtitle: String
        if let actor = approvalSummary.latestApprover {
            subtitle = "\(actor.login) · \(repository) · Ready to merge"
        } else {
            subtitle = "\(repository) · Ready to merge"
        }

        return ReadyToMergeSummary(
            id: "\(repository)#\(issue.number)",
            ignoreKey: details.htmlURL.absoluteString,
            number: issue.number,
            title: issue.title,
            subtitle: subtitle,
            repository: repository,
            url: details.htmlURL,
            updatedAt: issue.updatedAt,
            actor: approvalSummary.latestApprover,
            approvalCount: approvalSummary.approvalCount
        )
    }

    private func fetchActionableNotifications(
        token: String,
        login: String,
        scanState: NotificationScanState,
        teamMembershipCache: TeamMembershipCache,
        observer: GitHubRateLimitObserver
    ) async throws -> NotificationFetchResult {
        let threadScan = try await fetchNotificationThreads(
            token: token,
            scanState: scanState,
            observer: observer
        )

        let enrichedThreads = Array(threadScan.candidates.prefix(notificationEnrichmentLimit))
        let fallbackThreads = await filterFallbackThreads(
            Array(threadScan.candidates.dropFirst(notificationEnrichmentLimit)),
            token: token,
            login: login,
            teamMembershipCache: teamMembershipCache,
            observer: observer
        )

        let fallbackSummaries = fallbackThreads.map(buildFallbackNotificationSummary)

        return await withTaskGroup(of: NotificationSummary?.self) { group in
            for thread in enrichedThreads {
                group.addTask {
                    do {
                        return try await buildNotificationSummary(
                            token: token,
                            login: login,
                            thread: thread.thread,
                            teamMembershipCache: teamMembershipCache,
                            observer: observer
                        )
                    } catch {
                        return nil
                    }
                }
            }

            var items = fallbackSummaries
            for await item in group {
                if let item {
                    items.append(item)
                }
            }

            let sortedItems = items.sorted { $0.updatedAt > $1.updatedAt }
            let visibleThreadIDs = Set(sortedItems.map(\.id))
            let deepestVisiblePage = threadScan.candidates
                .filter { visibleThreadIDs.contains($0.thread.id) }
                .map(\.page)
                .max() ?? steadyNotificationPageLimit

            return NotificationFetchResult(
                notifications: sortedItems,
                scanState: NotificationScanState(
                    knownActionableThreadIDs: sortedItems.map(\.id),
                    preferredPageDepth: deepestVisiblePage
                ).normalized
            )
        }
    }

    private func fetchNotificationThreads(
        token: String,
        scanState: NotificationScanState,
        observer: GitHubRateLimitObserver
    ) async throws -> NotificationThreadScan {
        let normalizedScanState = scanState.normalized
        let knownActionableThreadIDs = Set(normalizedScanState.knownActionableThreadIDs)
        let minimumPageTarget: Int
        if knownActionableThreadIDs.isEmpty {
            minimumPageTarget = initialNotificationPageLimit
        } else {
            minimumPageTarget = max(steadyNotificationPageLimit, normalizedScanState.preferredPageDepth)
        }

        var candidateThreads: [NotificationThreadCandidate] = []

        for page in 1...maximumNotificationPageLimit {
            let threads: [NotificationThread] = try await request(
                path: "/notifications",
                queryItems: [
                    URLQueryItem(name: "all", value: "false"),
                    URLQueryItem(name: "per_page", value: "\(notificationPageSize)"),
                    URLQueryItem(name: "page", value: "\(page)")
                ],
                token: token,
                observer: observer
            )

            let actionableThreads = threads.filter {
                NotificationAttentionPolicy.isActionable(reason: $0.reason)
            }
            candidateThreads.append(
                contentsOf: actionableThreads.map {
                    NotificationThreadCandidate(thread: $0, page: page)
                }
            )

            let pageContainsKnownActionable = !knownActionableThreadIDs.isEmpty &&
                actionableThreads.contains { knownActionableThreadIDs.contains($0.id) }
            let shouldStopAfterThisPage = page >= minimumPageTarget && (
                actionableThreads.isEmpty ||
                    pageContainsKnownActionable ||
                    candidateThreads.count >= actionableNotificationLimit
            )

            if threads.count < notificationPageSize || shouldStopAfterThisPage {
                break
            }
        }

        return NotificationThreadScan(
            candidates: Array(candidateThreads.prefix(actionableNotificationLimit))
        )
    }

    private func buildNotificationSummary(
        token: String,
        login: String,
        thread: NotificationThread,
        teamMembershipCache: TeamMembershipCache,
        observer: GitHubRateLimitObserver
    ) async throws -> NotificationSummary? {
        var actor: AttentionActor?
        var reviewTarget: ReviewRequestTarget?
        var timelineContext: TimelineContext?
        var type = AttentionItemType.notificationType(
            reason: thread.reason,
            timelineEvent: nil,
            reviewState: nil
        )
        var ignoreKey: String?

        if let reference = discussionReference(from: thread.subject.url) {
            ignoreKey = canonicalIgnoreURL(for: reference)?.absoluteString

            if reference.kind == .pullRequest {
                let state = try await fetchPullRequestState(
                    token: token,
                    reference: reference,
                    observer: observer
                )
                guard PullRequestAttentionPolicy.shouldIncludeActivity(
                    state: state.state,
                    merged: state.merged,
                    closedAt: state.closedAt
                ) else {
                    return nil
                }

                if thread.reason == "review_requested" {
                    reviewTarget = try await fetchReviewRequestTarget(
                        token: token,
                        reference: reference,
                        login: login,
                        teamMembershipCache: teamMembershipCache,
                        observer: observer
                    )
                }
            }

            if let fetchedTimelineContext = try await fetchTimelineContext(
                    token: token,
                    reference: reference,
                    currentLogin: login,
                    reviewTarget: reviewTarget,
                    teamMembershipCache: teamMembershipCache,
                    observer: observer
                ) {
                timelineContext = fetchedTimelineContext
                actor = fetchedTimelineContext.actor
                type = AttentionItemType.notificationType(
                    reason: thread.reason,
                    timelineEvent: fetchedTimelineContext.event,
                    reviewState: fetchedTimelineContext.reviewState,
                    teamScoped: thread.reason == "team_mention" || reviewTarget?.isTeam == true,
                    followUpRelationship: fetchedTimelineContext.followUpRelationship
                )
            }
        }

        if actor == nil {
            type = AttentionItemType.notificationType(
                reason: thread.reason,
                timelineEvent: nil,
                reviewState: nil,
                teamScoped: thread.reason == "team_mention" || reviewTarget?.isTeam == true
            )
        }

        let repository = thread.repository.fullName
        let url = subjectWebURL(
            subjectURL: thread.subject.url,
            repositoryWebURL: thread.repository.htmlURL,
            subjectType: thread.subject.type
        )

        return NotificationSummary(
            id: thread.id,
            ignoreKey: ignoreKey ?? url.absoluteString,
            type: type,
            title: thread.subject.title,
            subtitle: notificationSubtitle(
                type: type,
                repository: repository,
                actor: actor,
                stateTransition: timelineContext?.stateTransition
            ),
            repository: repository,
            url: url,
            updatedAt: thread.updatedAt,
            unread: thread.unread,
            actor: actor,
            targetLabel: notificationTargetLabel(
                reason: thread.reason,
                type: type,
                reviewTarget: reviewTarget,
                followUpRelationship: timelineContext?.followUpRelationship,
                stateTransition: timelineContext?.stateTransition
            ),
            stateTransition: timelineContext?.stateTransition,
            detailEvidence: timelineContext?.detailEvidence ?? []
        )
    }

    private func buildFallbackNotificationSummary(
        _ candidate: FallbackNotificationCandidate
    ) -> NotificationSummary {
        let thread = candidate.thread
        let type = AttentionItemType.notificationType(
            reason: thread.reason,
            timelineEvent: nil,
            reviewState: nil,
            teamScoped: candidate.reviewTarget?.isTeam == true
        )
        let reference = discussionReference(from: thread.subject.url)
        let ignoreKey = reference.flatMap { canonicalIgnoreURL(for: $0)?.absoluteString }
        let repository = thread.repository.fullName
        let url = subjectWebURL(
            subjectURL: thread.subject.url,
            repositoryWebURL: thread.repository.htmlURL,
            subjectType: thread.subject.type
        )

        return NotificationSummary(
            id: thread.id,
            ignoreKey: ignoreKey ?? url.absoluteString,
            type: type,
            title: thread.subject.title,
            subtitle: notificationSubtitle(
                type: type,
                repository: repository,
                actor: nil,
                stateTransition: nil
            ),
            repository: repository,
            url: url,
            updatedAt: thread.updatedAt,
            unread: thread.unread,
            actor: nil,
            targetLabel: notificationTargetLabel(
                reason: thread.reason,
                type: type,
                reviewTarget: candidate.reviewTarget,
                followUpRelationship: nil,
                stateTransition: nil
            ),
            stateTransition: nil,
            detailEvidence: []
        )
    }

    private func filterFallbackThreads(
        _ threads: [NotificationThreadCandidate],
        token: String,
        login: String,
        teamMembershipCache: TeamMembershipCache,
        observer: GitHubRateLimitObserver
    ) async -> [FallbackNotificationCandidate] {
        await withTaskGroup(of: (Int, FallbackNotificationCandidate?).self) { group in
            for (index, thread) in threads.enumerated() {
                group.addTask {
                    do {
                        let candidate = try await fallbackNotificationCandidate(
                            thread.thread,
                            token: token,
                            login: login,
                            teamMembershipCache: teamMembershipCache,
                            observer: observer
                        )
                        return (index, candidate)
                    } catch {
                        return (index, nil)
                    }
                }
            }

            var filtered = Array<FallbackNotificationCandidate?>(repeating: nil, count: threads.count)
            for await (index, thread) in group {
                filtered[index] = thread
            }

            return filtered.compactMap { $0 }
        }
    }

    private func fallbackNotificationCandidate(
        _ thread: NotificationThread,
        token: String,
        login: String,
        teamMembershipCache: TeamMembershipCache,
        observer: GitHubRateLimitObserver
    ) async throws -> FallbackNotificationCandidate? {
        guard NotificationAttentionPolicy.shouldIncludeFallback(
            reason: thread.reason,
            updatedAt: thread.updatedAt
        ) else {
            return nil
        }

        guard
            let reference = discussionReference(from: thread.subject.url),
            reference.kind == .pullRequest
        else {
            return FallbackNotificationCandidate(thread: thread, reviewTarget: nil)
        }

        let state = try await fetchPullRequestState(
            token: token,
            reference: reference,
            observer: observer
        )
        guard NotificationAttentionPolicy.shouldIncludePullRequestFallback(
            state: state.state,
            merged: state.merged
        ) else {
            return nil
        }

        if thread.reason == "review_requested" {
            let reviewTarget = try await fetchReviewRequestTarget(
                token: token,
                reference: reference,
                login: login,
                teamMembershipCache: teamMembershipCache,
                observer: observer
            )
            guard let reviewTarget else {
                return nil
            }
            return FallbackNotificationCandidate(thread: thread, reviewTarget: reviewTarget)
        }

        return FallbackNotificationCandidate(thread: thread, reviewTarget: nil)
    }

    private func fetchTimelineContext(
        token: String,
        reference: DiscussionReference,
        currentLogin: String,
        reviewTarget: ReviewRequestTarget?,
        teamMembershipCache: TeamMembershipCache,
        observer: GitHubRateLimitObserver
    ) async throws -> TimelineContext? {
        let timeline: [TimelineEntry] = try await request(
            path: "/repos/\(reference.owner)/\(reference.name)/issues/\(reference.number)/timeline",
            queryItems: [
                URLQueryItem(name: "per_page", value: "50")
            ],
            token: token,
            observer: observer
        )

        let sortedTimeline = timeline.sorted {
            (timelineTimestamp(for: $0, fallbackToDistantPast: true) ?? .distantPast)
                > (timelineTimestamp(for: $1, fallbackToDistantPast: true) ?? .distantPast)
        }

        for entry in sortedTimeline {
            guard let timestamp = timelineTimestamp(for: entry) else {
                continue
            }

            let event = (entry.event ?? "").lowercased()
            guard !event.isEmpty else {
                continue
            }

            guard !timelineActorMatches(entry, login: currentLogin) else {
                continue
            }

            switch event {
            case "assigned":
                guard timelineUser(entry.assignee, matches: currentLogin) else {
                    continue
                }
            case "review_requested":
                let requestedReviewerMatches = timelineUser(entry.requestedReviewer, matches: currentLogin)
                let requestedTeamMatches = timelineTeam(
                    entry.requestedTeam,
                    owner: reference.owner,
                    reviewTarget: reviewTarget,
                    teamMembershipCache: teamMembershipCache
                )
                guard requestedReviewerMatches || requestedTeamMatches else {
                    continue
                }
            case "closed",
                "commented",
                "committed",
                "head_ref_force_pushed",
                "merged",
                "reopened",
                "reviewed":
                break
            default:
                continue
            }

            let followUp = followUpRelationship(
                in: sortedTimeline,
                latestChangeAt: timestamp,
                currentLogin: currentLogin
            )

            let detailEvidence: [AttentionEvidence]
            let stateTransition: PullRequestStateTransition?
            if event == "committed" || event == "head_ref_force_pushed",
                let followUp {
                detailEvidence = commitEvidence(
                    in: sortedTimeline,
                    reference: reference,
                    after: followUp.timestamp,
                    currentLogin: currentLogin
                )
                stateTransition = .synchronized
            } else if event == "merged" {
                detailEvidence = []
                stateTransition = .merged
            } else if event == "closed" {
                detailEvidence = []
                stateTransition = .closed
            } else if event == "reopened" {
                detailEvidence = []
                stateTransition = .reopened
            } else {
                detailEvidence = []
                stateTransition = nil
            }

            return TimelineContext(
                event: event,
                reviewState: entry.state,
                actor: timelineActor(from: entry),
                timestamp: timestamp,
                followUpRelationship: followUp?.relationship,
                stateTransition: stateTransition,
                detailEvidence: detailEvidence
            )
        }

        return nil
    }

    private func notificationSubtitle(
        type: AttentionItemType,
        repository: String,
        actor: AttentionActor?,
        stateTransition: PullRequestStateTransition?
    ) -> String {
        if type == .pullRequestStateChanged, let stateTransition {
            if let actor {
                return "\(actor.login) · \(repository) · \(stateTransition.detailLabel)"
            }

            return "\(repository) · \(stateTransition.detailLabel)"
        }

        if let actor {
            return "\(actor.login) · \(repository) · \(type.accessibilityLabel)"
        }

        return "\(repository) · \(type.accessibilityLabel)"
    }

    private func fetchReviewRequestTarget(
        token: String,
        reference: DiscussionReference,
        login: String,
        teamMembershipCache: TeamMembershipCache,
        observer: GitHubRateLimitObserver
    ) async throws -> ReviewRequestTarget? {
        guard reference.kind == .pullRequest else {
            return nil
        }

        let response: RequestedReviewersResponse = try await request(
            path: "/repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)/requested_reviewers",
            token: token,
            observer: observer
        )

        if response.users.contains(where: { $0.login.caseInsensitiveCompare(login) == .orderedSame }) {
            return .direct
        }

        let matchingTeams = response.teams.filter {
            teamMembershipCache.contains(owner: reference.owner, slug: $0.slug)
        }
        if let team = matchingTeams.first {
            return .team(
                owner: reference.owner,
                slug: team.slug,
                name: team.name ?? team.slug
            )
        }

        guard !response.teams.isEmpty else {
            return nil
        }

        if teamMembershipCache.fetchedAt != nil {
            return nil
        }

        if response.teams.count == 1, let team = response.teams.first {
            return .team(
                owner: reference.owner,
                slug: team.slug,
                name: team.name ?? team.slug
            )
        }

        return .team(owner: reference.owner, slug: nil, name: nil)
    }

    private func notificationTargetLabel(
        reason: String,
        type: AttentionItemType,
        reviewTarget: ReviewRequestTarget?,
        followUpRelationship: NotificationFollowUpRelationship?,
        stateTransition: PullRequestStateTransition?
    ) -> String? {
        switch followUpRelationship {
        case .afterYourComment:
            return "New commits landed after you commented."
        case .afterYourReview:
            return "New commits landed after your review."
        case nil:
            break
        }

        if type == .pullRequestStateChanged, let stateTransition {
            return stateTransition.detailLabel
        }

        switch reason.lowercased() {
        case "assign":
            return "Assigned to you directly."
        case "mention":
            return "You were mentioned directly."
        case "team_mention":
            return "One of your teams was mentioned."
        case "review_requested":
            switch reviewTarget {
            case .direct:
                return "Review was requested from you directly."
            case let .team(_, _, name):
                if let name, !name.isEmpty {
                    return "Review was requested from team \(name)."
                }
                return "Review was requested from one of your teams."
            case nil:
                return type == .teamReviewRequested
                    ? "Review was requested from one of your teams."
                    : "Review was requested from you."
            }
        default:
            return nil
        }
    }

    private func followUpRelationship(
        in timeline: [TimelineEntry],
        latestChangeAt: Date,
        currentLogin: String
    ) -> (relationship: NotificationFollowUpRelationship, timestamp: Date)? {
        for entry in timeline {
            guard let timestamp = timelineTimestamp(for: entry), timestamp < latestChangeAt else {
                continue
            }

            guard timelineActorMatches(entry, login: currentLogin) else {
                continue
            }

            switch (entry.event ?? "").lowercased() {
            case "commented":
                return (.afterYourComment, timestamp)
            case "reviewed":
                return (.afterYourReview, timestamp)
            default:
                continue
            }
        }

        return nil
    }

    private func commitEvidence(
        in timeline: [TimelineEntry],
        reference: DiscussionReference,
        after participationTimestamp: Date,
        currentLogin: String
    ) -> [AttentionEvidence] {
        timeline.compactMap { entry -> AttentionEvidence? in
            guard let timestamp = timelineTimestamp(for: entry), timestamp > participationTimestamp else {
                return nil
            }

            guard !timelineActorMatches(entry, login: currentLogin) else {
                return nil
            }

            let event = (entry.event ?? "").lowercased()
            guard event == "committed" || event == "head_ref_force_pushed" else {
                return nil
            }

            let sha = (entry.sha ?? entry.commitID)?.prefix(7)
            let title = timelineCommitTitle(for: entry, abbreviatedSHA: sha.map(String.init))
            let detail = timelineCommitDetail(for: entry, abbreviatedSHA: sha.map(String.init))

            return AttentionEvidence(
                id: "commit-\(entry.id.map(String.init) ?? UUID().uuidString)",
                title: title,
                detail: detail,
                iconName: event == "head_ref_force_pushed" ? "arrow.uturn.backward.circle" : "arrow.trianglehead.branch",
                url: timelineCommitURL(for: entry, reference: reference)
            )
        }
        .prefix(3)
        .map { $0 }
    }

    private func timelineCommitTitle(for entry: TimelineEntry, abbreviatedSHA: String?) -> String {
        if let message = entry.message?.split(separator: "\n").first,
            !message.isEmpty {
            return String(message)
        }

        if (entry.event ?? "").lowercased() == "head_ref_force_pushed" {
            return "Force-pushed branch"
        }

        if let abbreviatedSHA {
            return "Commit \(abbreviatedSHA)"
        }

        return "New commit"
    }

    private func timelineCommitDetail(for entry: TimelineEntry, abbreviatedSHA: String?) -> String? {
        if let abbreviatedSHA,
            let message = entry.message?.split(separator: "\n").first,
            !message.isEmpty {
            return abbreviatedSHA
        }

        return abbreviatedSHA
    }

    private func timelineCommitURL(for entry: TimelineEntry, reference: DiscussionReference) -> URL? {
        if let htmlURL = entry.htmlURL {
            return htmlURL
        }

        if let sha = entry.sha ?? entry.commitID {
            return URL(string: "https://github.com/\(reference.owner)/\(reference.name)/commit/\(sha)")
        }

        if let commitURL = entry.commitURL {
            return subjectWebURL(
                subjectURL: commitURL,
                repositoryWebURL: repositoryWebURL(repository: "\(reference.owner)/\(reference.name)"),
                subjectType: "Commit"
            )
        }

        return nil
    }

    private func timelineTimestamp(
        for entry: TimelineEntry,
        fallbackToDistantPast: Bool = false
    ) -> Date? {
        let timestamp = entry.submittedAt ?? entry.createdAt
        if fallbackToDistantPast, timestamp == nil {
            return .distantPast
        }
        return timestamp
    }

    private func timelineActor(from entry: TimelineEntry) -> AttentionActor? {
        attentionActor(from: entry.actor ?? entry.user) ??
            attentionActor(from: entry.committer) ??
            attentionActor(from: entry.author)
    }

    private func timelineActorMatches(_ entry: TimelineEntry, login: String) -> Bool {
        timelineActor(from: entry)?.login.caseInsensitiveCompare(login) == .orderedSame
    }

    private func timelineUser(_ user: GitHubUser?, matches login: String) -> Bool {
        user?.login.caseInsensitiveCompare(login) == .orderedSame
    }

    private func timelineTeam(
        _ team: GitHubTeam?,
        owner: String,
        reviewTarget: ReviewRequestTarget?,
        teamMembershipCache: TeamMembershipCache
    ) -> Bool {
        guard let team else {
            return false
        }

        if reviewTarget?.matches(owner: owner, slug: team.slug) == true {
            return true
        }

        return reviewTarget == nil && teamMembershipCache.contains(owner: owner, slug: team.slug)
    }

    private func discussionReference(from subjectURL: URL?) -> DiscussionReference? {
        guard let subjectURL else {
            return nil
        }

        let parts = subjectURL.pathComponents
        guard let reposIndex = parts.firstIndex(of: "repos"), reposIndex + 4 < parts.count else {
            return nil
        }

        let owner = parts[reposIndex + 1]
        let name = parts[reposIndex + 2]
        let subjectKind = parts[reposIndex + 3]
        guard let number = Int(parts[reposIndex + 4]) else {
            return nil
        }

        switch subjectKind {
        case "pulls":
            return DiscussionReference(owner: owner, name: name, number: number, kind: .pullRequest)
        case "issues":
            return DiscussionReference(owner: owner, name: name, number: number, kind: .issue)
        default:
            return nil
        }
    }

    private func fetchPullRequestState(
        token: String,
        reference: DiscussionReference,
        observer: GitHubRateLimitObserver
    ) async throws -> PullRequestStateResponse {
        try await request(
            path: "/repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)",
            token: token,
            observer: observer
        )
    }

    private func fetchWatchedWorkflowRuns(
        token: String,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [ActionRunSummary] {
        let candidates = try await fetchWorkflowWatchCandidates(
            token: token,
            login: login,
            observer: observer
        )

        return await withTaskGroup(of: [ActionRunSummary].self) { group in
            for candidate in candidates {
                group.addTask {
                    do {
                        return try await fetchWorkflowRuns(
                            token: token,
                            login: login,
                            candidate: candidate,
                            observer: observer
                        )
                    } catch {
                        return []
                    }
                }
            }

            var mergedByRunID = [String: ActionRunSummary]()
            for await runs in group {
                for run in runs {
                    if let existing = mergedByRunID[run.id], existing.createdAt >= run.createdAt {
                        continue
                    }
                    mergedByRunID[run.id] = run
                }
            }

            return mergedByRunID.values.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func fetchWorkflowWatchCandidates(
        token: String,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [WorkflowWatchCandidate] {
        async let authoredTask = searchWorkflowWatchCandidates(
            token: token,
            query: "is:pr author:\(login) archived:false",
            relationship: .authored,
            observer: observer
        )
        async let approvedTask = searchWorkflowWatchCandidates(
            token: token,
            query: "is:pr reviewed-by:\(login) archived:false",
            relationship: .approved,
            observer: observer
        )
        async let mergedTask = searchWorkflowWatchCandidates(
            token: token,
            query: "is:pr is:merged merged-by:\(login) archived:false",
            relationship: .merged,
            observer: observer
        )

        let authored = try await authoredTask
        let approved = try await approvedTask
        let merged = try await mergedTask

        var byKey = [String: WorkflowWatchCandidate]()
        for candidate in authored + approved + merged {
            let key = "\(candidate.repository)#\(candidate.number)"
            if let existing = byKey[key], existing.relationship.priority >= candidate.relationship.priority {
                continue
            }
            byKey[key] = candidate
        }

        return byKey.values
            .sorted { lhs, rhs in
                if lhs.relationship.priority == rhs.relationship.priority {
                    return lhs.number > rhs.number
                }
                return lhs.relationship.priority > rhs.relationship.priority
            }
            .prefix(workflowCandidateLimit)
            .map { $0 }
    }

    private func searchWorkflowWatchCandidates(
        token: String,
        query: String,
        relationship: WorkflowWatchRelationship,
        observer: GitHubRateLimitObserver
    ) async throws -> [WorkflowWatchCandidate] {
        let response: SearchIssuesResponse = try await request(
            path: "/search/issues",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "per_page", value: "\(workflowCandidateLimit)")
            ],
            token: token,
            observer: observer
        )

        return response.items.compactMap { issue in
            guard let repository = repositoryFullName(from: issue.repositoryURL) else {
                return nil
            }

            return WorkflowWatchCandidate(
                repository: repository,
                number: issue.number,
                relationship: relationship
            )
        }
    }

    private func fetchWorkflowRuns(
        token: String,
        login: String,
        candidate: WorkflowWatchCandidate,
        observer: GitHubRateLimitObserver
    ) async throws -> [ActionRunSummary] {
        let repositoryID = try parseRepositoryFullName(candidate.repository)
        let pullRequest: PullRequestDetails = try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/pulls/\(candidate.number)",
            token: token,
            observer: observer
        )

        if candidate.relationship == .approved {
            guard try await didUserApprovePullRequest(
                token: token,
                repository: candidate.repository,
                number: candidate.number,
                login: login,
                observer: observer
            ) else {
                return []
            }
        }

        guard PullRequestAttentionPolicy.shouldWatchWorkflows(
            state: pullRequest.state,
            merged: pullRequest.merged,
            mergedAt: pullRequest.mergedAt
        ) else {
            return []
        }

        let commitSHA: String
        if pullRequest.merged {
            guard let mergeCommitSHA = pullRequest.mergeCommitSHA else {
                return []
            }
            commitSHA = mergeCommitSHA
        } else {
            commitSHA = pullRequest.head.sha
        }

        let runs = try await fetchWorkflowRunsForCommit(
            token: token,
            repository: candidate.repository,
            commitSHA: commitSHA,
            observer: observer
        )

        return runs.compactMap { run in
            guard let type = AttentionItemType.workflowType(
                status: run.status,
                conclusion: run.conclusion
            ) else {
                return nil
            }

            let actor = attentionActor(from: run.triggeringActor ?? run.actor)
            let summaryTitle = run.displayTitle ?? run.name ?? "Workflow run"
            let summarySubtitle = workflowSubtitle(
                type: type,
                actor: actor,
                repository: candidate.repository,
                number: candidate.number
            )

            return ActionRunSummary(
                id: "\(candidate.repository)-\(run.id)",
                ignoreKey: pullRequestWebURL(
                    repository: candidate.repository,
                    number: candidate.number
                ).absoluteString,
                type: type,
                title: summaryTitle,
                subtitle: summarySubtitle,
                repository: candidate.repository,
                createdAt: run.createdAt,
                url: run.htmlURL ?? runWebURL(repository: candidate.repository, runID: run.id),
                actor: actor
            )
        }
    }

    private func didUserApprovePullRequest(
        token: String,
        repository: String,
        number: Int,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> Bool {
        let reviews = try await fetchPullRequestReviews(
            token: token,
            repository: repository,
            number: number,
            observer: observer
        )

        return reviews.contains {
            $0.user.login.caseInsensitiveCompare(login) == .orderedSame &&
                $0.state.caseInsensitiveCompare("APPROVED") == .orderedSame
        }
    }

    private func fetchPullRequestReviews(
        token: String,
        repository: String,
        number: Int,
        observer: GitHubRateLimitObserver
    ) async throws -> [PullRequestReview] {
        let repositoryID = try parseRepositoryFullName(repository)
        return try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/pulls/\(number)/reviews",
            queryItems: [
                URLQueryItem(name: "per_page", value: "100")
            ],
            token: token,
            observer: observer
        )
    }

    private func latestApprovalSummary(
        reviews: [PullRequestReview],
        excluding login: String
    ) -> LatestApprovalSummary {
        var latestByReviewer = [String: PullRequestReview]()

        for review in reviews {
            guard review.user.login.caseInsensitiveCompare(login) != .orderedSame else {
                continue
            }

            let key = review.user.login.lowercased()
            if let existing = latestByReviewer[key],
                existing.submittedAt >= review.submittedAt {
                continue
            }
            latestByReviewer[key] = review
        }

        let latestReviews = Array(latestByReviewer.values)
        let approvals = latestReviews.filter {
            $0.state.caseInsensitiveCompare("APPROVED") == .orderedSame
        }
        let latestApprover = approvals.max { lhs, rhs in
            lhs.submittedAt < rhs.submittedAt
        }.flatMap { attentionActor(from: $0.user) }

        return LatestApprovalSummary(
            approvalCount: approvals.count,
            hasChangesRequested: latestReviews.contains {
                $0.state.caseInsensitiveCompare("CHANGES_REQUESTED") == .orderedSame
            },
            latestApprover: latestApprover
        )
    }

    private func latestApprovalSummary(
        reviews: [PullRequestFocusGraphQLReview],
        excluding login: String
    ) -> LatestApprovalSummary {
        var latestByReviewer = [String: PullRequestFocusGraphQLReview]()

        for review in reviews {
            guard let reviewer = review.author?.login,
                reviewer.caseInsensitiveCompare(login) != .orderedSame else {
                continue
            }

            let key = reviewer.lowercased()
            if let existing = latestByReviewer[key],
                existing.submittedAt >= review.submittedAt {
                continue
            }
            latestByReviewer[key] = review
        }

        let latestReviews = Array(latestByReviewer.values)
        let approvals = latestReviews.filter {
            $0.state.caseInsensitiveCompare("APPROVED") == .orderedSame
        }
        let latestApprover = approvals.max { lhs, rhs in
            lhs.submittedAt < rhs.submittedAt
        }.flatMap { attentionActor(from: $0.author) }

        return LatestApprovalSummary(
            approvalCount: approvals.count,
            hasChangesRequested: latestReviews.contains {
                $0.state.caseInsensitiveCompare("CHANGES_REQUESTED") == .orderedSame
            },
            latestApprover: latestApprover
        )
    }

    private func fetchWorkflowRunsForCommit(
        token: String,
        repository: String,
        commitSHA: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [WorkflowRun] {
        let repositoryID = try parseRepositoryFullName(repository)
        let response: WorkflowRunsResponse = try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/actions/runs",
            queryItems: [
                URLQueryItem(name: "head_sha", value: commitSHA),
                URLQueryItem(name: "per_page", value: "\(workflowRunLimit)")
            ],
            token: token,
            observer: observer
        )

        return response.workflowRuns
    }

    private func fetchPostMergeWorkflowPreview(
        token: String,
        reference: PullRequestReference,
        branch: String,
        mergeCommitSHA: String?,
        observer: GitHubRateLimitObserver
    ) async throws -> PullRequestPostMergeWorkflowPreview? {
        let predicted = try await fetchPredictedPostMergeWorkflows(
            token: token,
            reference: reference,
            branch: branch,
            observer: observer
        )
        let observed: [PostMergeObservedWorkflowRun]
        if let mergeCommitSHA {
            let runs = try await fetchWorkflowRunsForCommit(
                token: token,
                repository: reference.repository,
                commitSHA: mergeCommitSHA,
                observer: observer
            )
            observed = postMergeObservedWorkflowRuns(
                from: runs,
                repository: reference.repository
            )
        } else {
            observed = []
        }

        guard !predicted.workflows.isEmpty || !observed.isEmpty else {
            return nil
        }

        return buildPostMergeWorkflowPreview(
            branch: branch,
            predicted: predicted.workflows,
            observed: observed,
            isMerged: mergeCommitSHA != nil,
            isBestEffort: predicted.isBestEffort
        )
    }

    private func repositoryActionsURL(repository: String) -> URL {
        URL(string: "https://github.com/\(repository)/actions")!
    }

    private func repositoryWorkflowURL(
        repository: String,
        path: String
    ) -> URL {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return URL(string: "https://github.com/\(repository)/actions/workflows/\(filename)")!
    }

    private func fetchPredictedPostMergeWorkflows(
        token: String,
        reference: PullRequestReference,
        branch: String,
        observer: GitHubRateLimitObserver
    ) async throws -> PredictedPostMergeWorkflowSet {
        let workflows = try await fetchRepositoryWorkflows(
            token: token,
            repository: reference.repository,
            observer: observer
        )
        guard !workflows.isEmpty else {
            return PredictedPostMergeWorkflowSet(workflows: [], isBestEffort: false)
        }

        let changedFiles = try await fetchPullRequestChangedFiles(
            token: token,
            reference: reference,
            observer: observer
        )
        guard !changedFiles.isEmpty else {
            return PredictedPostMergeWorkflowSet(workflows: [], isBestEffort: false)
        }

        return await withTaskGroup(of: PredictedPostMergeWorkflowOutcome.self) { group in
            for workflow in workflows {
                group.addTask {
                    do {
                        guard
                            let content = try await self.fetchRepositoryFileContent(
                                token: token,
                                repository: reference.repository,
                                path: workflow.path,
                                ref: branch,
                                observer: observer
                            ),
                            let definition = GitHubWorkflowFileParser.parse(content)
                        else {
                            return .bestEffortOnly
                        }

                        guard let pushTrigger = definition.pushTrigger else {
                            return .ignored
                        }

                        guard GitHubWorkflowPathFilterPolicy.matches(
                            trigger: pushTrigger,
                            branch: branch,
                            changedFiles: changedFiles
                        ) else {
                            return .ignored
                        }

                        let title = definition.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return .matched(
                            PredictedPostMergeWorkflow(
                                id: workflow.id,
                                title: title?.isEmpty == false ? title! : workflow.name,
                                url: workflow.htmlURL ?? self.repositoryWorkflowURL(
                                    repository: reference.repository,
                                    path: workflow.path
                                )
                            )
                        )
                    } catch {
                        return .bestEffortOnly
                    }
                }
            }

            var predicted = [PredictedPostMergeWorkflow]()
            var isBestEffort = false

            for await outcome in group {
                switch outcome {
                case let .matched(workflow):
                    predicted.append(workflow)
                case .bestEffortOnly:
                    isBestEffort = true
                case .ignored:
                    break
                }
            }

            predicted.sort { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return PredictedPostMergeWorkflowSet(
                workflows: predicted,
                isBestEffort: isBestEffort
            )
        }
    }

    private func fetchRepositoryWorkflows(
        token: String,
        repository: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [RepositoryWorkflow] {
        let repositoryID = try parseRepositoryFullName(repository)
        let response: RepositoryWorkflowsResponse = try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/actions/workflows",
            token: token,
            observer: observer
        )

        return response.workflows.filter {
            $0.state.caseInsensitiveCompare("active") == .orderedSame
        }
    }

    private func fetchPullRequestChangedFiles(
        token: String,
        reference: PullRequestReference,
        observer: GitHubRateLimitObserver
    ) async throws -> [String] {
        var changedFiles = [String]()
        var page = 1

        while true {
            let files: [PullRequestFile] = try await request(
                path: "/repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)/files",
                queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ],
                token: token,
                observer: observer
            )

            changedFiles.append(contentsOf: files.map(\.filename))

            guard files.count == 100 else {
                break
            }

            page += 1
        }

        return changedFiles
    }

    private func fetchRepositoryFileContent(
        token: String,
        repository: String,
        path: String,
        ref: String,
        observer: GitHubRateLimitObserver
    ) async throws -> String? {
        let repositoryID = try parseRepositoryFullName(repository)

        do {
            let file: RepositoryContentFile = try await request(
                path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/contents/\(path)",
                queryItems: [
                    URLQueryItem(name: "ref", value: ref)
                ],
                token: token,
                observer: observer
            )

            guard file.type == "file", file.encoding == "base64", let encoded = file.content else {
                return nil
            }

            let normalized = encoded.replacingOccurrences(of: "\n", with: "")
            guard
                let data = Data(base64Encoded: normalized),
                let content = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            return content
        } catch let GitHubClientError.api(statusCode, _) where statusCode == 404 {
            return nil
        }
    }

    private func postMergeObservedWorkflowRuns(
        from runs: [WorkflowRun],
        repository: String
    ) -> [PostMergeObservedWorkflowRun] {
        runs.compactMap { run in
            guard run.event.caseInsensitiveCompare("push") == .orderedSame else {
                return nil
            }

            return PostMergeObservedWorkflowRun(
                id: run.id,
                workflowID: run.workflowID,
                title: run.displayTitle ?? run.name ?? "Workflow run",
                repository: repository,
                url: run.htmlURL ?? runWebURL(repository: repository, runID: run.id),
                event: run.event,
                status: run.status,
                conclusion: run.conclusion,
                createdAt: run.createdAt,
                actor: attentionActor(from: run.triggeringActor ?? run.actor)
            )
        }
    }

    private func buildPostMergeWorkflowPreview(
        branch: String,
        predicted: [PredictedPostMergeWorkflow],
        observed: [PostMergeObservedWorkflowRun],
        isMerged: Bool,
        isBestEffort: Bool
    ) -> PullRequestPostMergeWorkflowPreview? {
        var latestObservedByKey = [String: PostMergeObservedWorkflowRun]()
        for run in observed {
            let key = run.workflowID.map { "workflow:\($0)" } ?? "name:\(run.title.lowercased())"
            if let existing = latestObservedByKey[key], existing.createdAt >= run.createdAt {
                continue
            }

            latestObservedByKey[key] = run
        }

        var workflows = [PullRequestPostMergeWorkflow]()
        for workflow in predicted {
            let key = "workflow:\(workflow.id)"
            let fallbackKey = "name:\(workflow.title.lowercased())"
            let observedRun = latestObservedByKey.removeValue(forKey: key) ??
                latestObservedByKey.removeValue(forKey: fallbackKey)

            workflows.append(
                PullRequestPostMergeWorkflow(
                    id: key,
                    title: workflow.title,
                    url: observedRun?.url ?? workflow.url,
                    status: observedRun.map {
                        PullRequestPostMergeWorkflowStatus.observed(
                            status: $0.status,
                            conclusion: $0.conclusion
                        )
                    } ?? (isMerged ? .waiting : .expected),
                    timestamp: observedRun?.createdAt
                )
            )
        }

        for run in latestObservedByKey.values {
            workflows.append(
                PullRequestPostMergeWorkflow(
                    id: run.workflowID.map { "workflow:\($0)" } ?? "run:\(run.id)",
                    title: run.title,
                    url: run.url,
                    status: PullRequestPostMergeWorkflowStatus.observed(
                        status: run.status,
                        conclusion: run.conclusion
                    ),
                    timestamp: run.createdAt
                )
            )
        }

        guard !workflows.isEmpty else {
            return nil
        }

        workflows.sort { lhs, rhs in
            switch (lhs.timestamp, rhs.timestamp) {
            case let (.some(lhsTimestamp), .some(rhsTimestamp)) where lhsTimestamp != rhsTimestamp:
                return lhsTimestamp > rhsTimestamp
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        return PullRequestPostMergeWorkflowPreview(
            mode: isMerged ? .observed(branch: branch) : .predicted(branch: branch),
            workflows: Array(workflows.prefix(6)),
            isBestEffort: isBestEffort
        )
    }

    private func workflowSubtitle(
        type: AttentionItemType,
        actor: AttentionActor?,
        repository: String,
        number: Int
    ) -> String {
        let prLabel = "PR #\(number)"
        if let actor {
            return "\(actor.login) · \(repository) · \(prLabel) · \(type.accessibilityLabel)"
        }

        return "\(repository) · \(prLabel) · \(type.accessibilityLabel)"
    }

    private func whySummary(
        for type: AttentionItemType,
        actor: AttentionActor?,
        stateTransition: PullRequestStateTransition? = nil
    ) -> String {
        if type == .pullRequestStateChanged, let stateTransition {
            if let actor {
                return "\(actor.login) \(stateTransition.actorVerb)."
            }

            return stateTransition.detailLabel + "."
        }

        if let actor {
            return "\(actor.login) \(type.actorVerb)."
        }

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
            return "There is new discussion on a thread you are following."
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
            return "A pull request you are tracking has requested changes."
        case .reviewComment:
            return "A pull request you are tracking has new review feedback."
        case .pullRequestStateChanged:
            return "A pull request you are tracking changed state."
        case .ciActivity:
            return "GitHub Actions reported activity that needs attention."
        case .workflowFailed:
            return "A watched workflow run failed."
        case .workflowApprovalRequired:
            return "A watched workflow run is waiting for approval."
        }
    }

    private func openActionTitle(for url: URL) -> String {
        let path = url.path
        if path.contains("/pull/") {
            return "Open Pull Request"
        }
        if path.contains("/issues/") {
            return "Open Issue"
        }
        if path.contains("/actions/runs/") {
            return "Open Workflow Run"
        }
        if path.contains("/commit/") {
            return "Open Commit"
        }
        return "Open on GitHub"
    }

    private func attentionActor(from user: GitHubUser?) -> AttentionActor? {
        guard let user else {
            return nil
        }

        return AttentionActor(
            login: user.login,
            avatarURL: user.avatarURL,
            profileURL: user.htmlURL
        )
    }

    private func attentionActor(from actor: PullRequestFocusGraphQLActor?) -> AttentionActor? {
        guard let actor, !actor.login.isEmpty else {
            return nil
        }

        return AttentionActor(
            login: actor.login,
            avatarURL: actor.avatarURL,
            profileURL: actor.url,
            isBot: actor.isBotAccount
        )
    }

    private func attentionActor(from identity: TimelineIdentity?) -> AttentionActor? {
        guard let identity, let login = identity.login, !login.isEmpty else {
            return nil
        }

        return AttentionActor(
            login: login,
            avatarURL: identity.avatarURL,
            profileURL: identity.url
        )
    }

    private func canonicalIgnoreURL(for reference: DiscussionReference) -> URL? {
        switch reference.kind {
        case .pullRequest:
            return pullRequestWebURL(
                repository: "\(reference.owner)/\(reference.name)",
                number: reference.number
            )
        case .issue:
            return issueWebURL(
                repository: "\(reference.owner)/\(reference.name)",
                number: reference.number
            )
        }
    }

    private func pullRequestWebURL(repository: String, number: Int) -> URL {
        URL(string: "https://github.com/\(repository)/pull/\(number)")!
    }

    private func issueWebURL(repository: String, number: Int) -> URL {
        URL(string: "https://github.com/\(repository)/issues/\(number)")!
    }

    private func repositoryWebURL(repository: String) -> URL {
        URL(string: "https://github.com/\(repository)")!
    }

    private func subjectLabel(for url: URL) -> String {
        let components = url.pathComponents

        if let pullIndex = components.firstIndex(of: "pull"),
            pullIndex >= 2,
            pullIndex + 1 < components.count {
            let repository = "\(components[pullIndex - 2])/\(components[pullIndex - 1])"
            return "\(repository) · PR #\(components[pullIndex + 1])"
        }

        if let issueIndex = components.firstIndex(of: "issues"),
            issueIndex >= 2,
            issueIndex + 1 < components.count {
            let repository = "\(components[issueIndex - 2])/\(components[issueIndex - 1])"
            return "\(repository) · Issue #\(components[issueIndex + 1])"
        }

        return url.absoluteString
    }

    private func parseRepositoryFullName(_ repository: String) throws -> RepositoryIdentifier {
        let split = repository.split(separator: "/", maxSplits: 1).map(String.init)
        guard split.count == 2 else {
            throw GitHubClientError.unsupportedRepositoryName(repository)
        }

        return RepositoryIdentifier(owner: split[0], name: split[1])
    }

    private func runWebURL(repository: String, runID: Int) -> URL {
        URL(string: "https://github.com/\(repository)/actions/runs/\(runID)")!
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String,
        observer: GitHubRateLimitObserver? = nil
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw GitHubClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Octowatch", forHTTPHeaderField: "User-Agent")

        let data = try await perform(request, observer: observer)
        return try decoder.decode(Response.self, from: data)
    }

    private func conditionalRequest<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        accept: String = "application/vnd.github+json",
        ifNoneMatch: String?,
        token: String,
        observer: GitHubRateLimitObserver? = nil
    ) async throws -> ConditionalRequestResult<Response> {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw GitHubClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Octowatch", forHTTPHeaderField: "User-Agent")
        if let ifNoneMatch, !ifNoneMatch.isEmpty {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await performResponse(request, observer: observer)
        let etag = Self.headerString("ETag", in: response)

        if response.statusCode == 304 {
            return .notModified(etag: etag)
        }

        return .modified(
            value: try decoder.decode(Response.self, from: data),
            etag: etag
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        token: String,
        observer: GitHubRateLimitObserver? = nil
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw GitHubClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Octowatch", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(request, observer: observer)
        return try decoder.decode(Response.self, from: data)
    }

    private func graphQLRequest<Response: Decodable, Variables: Encodable>(
        query: String,
        variables: Variables,
        token: String,
        observer: GitHubRateLimitObserver? = nil
    ) async throws -> Response {
        var request = URLRequest(url: graphQLURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Octowatch", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            GraphQLRequest(
                query: query,
                variables: variables
            )
        )

        let data = try await perform(request, observer: observer)
        let response = try decoder.decode(GraphQLResponse<Response>.self, from: data)

        if let errors = response.errors, !errors.isEmpty {
            throw GitHubClientError.api(
                statusCode: 200,
                message: errors.map(\.message).joined(separator: " | ")
            )
        }

        guard let graphQLData = response.data else {
            throw GitHubClientError.invalidResponse
        }

        return graphQLData
    }

    private func perform(
        _ request: URLRequest,
        observer: GitHubRateLimitObserver? = nil
    ) async throws -> Data {
        let (data, _) = try await performResponse(request, observer: observer)
        return data
    }

    private func performResponse(
        _ request: URLRequest,
        observer: GitHubRateLimitObserver? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }

        let rateLimit = Self.parseRateLimit(from: http)
        if let observer, let rateLimit {
            await observer.record(rateLimit)
        }

        if http.statusCode == 401 {
            throw GitHubClientError.invalidCredentials
        }

        guard http.statusCode == 304 || (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(GitHubAPIError.self, from: data).message) ?? "Unknown error"
            if http.statusCode == 403 || http.statusCode == 429 {
                let lowercasedMessage = message.lowercased()
                if lowercasedMessage.contains("rate limit") || rateLimit?.isExhausted == true {
                    throw GitHubClientError.rateLimited(rateLimit)
                }
            }
            throw GitHubClientError.api(statusCode: http.statusCode, message: message)
        }

        return (data, http)
    }

    private func mapTokenValidationError(
        _ error: Error,
        fallback: String
    ) -> GitHubClientError {
        if let clientError = error as? GitHubClientError {
            switch clientError {
            case .invalidCredentials:
                return .invalidCredentials
            case let .api(statusCode, message):
                let lowercasedMessage = message.lowercased()
                if lowercasedMessage.contains("fine-grained") ||
                    lowercasedMessage.contains("notifications")
                {
                    return .tokenValidation(
                        message: """
                        This token cannot access GitHub notifications. Fine-grained \
                        personal access tokens do not support that API.
                        """
                    )
                }

                if statusCode == 403 || statusCode == 404 {
                    return .tokenValidation(message: fallback)
                }

                return .tokenValidation(message: "GitHub rejected this token: \(message)")
            case .rateLimited:
                return .tokenValidation(
                    message: "GitHub rate-limited the validation request. Try again in a few minutes."
                )
            case let .tokenValidation(message):
                return .tokenValidation(message: message)
            default:
                return .tokenValidation(message: fallback)
            }
        }

        return .tokenValidation(message: fallback)
    }

    private func repositoryFullName(from apiRepositoryURL: URL) -> String? {
        let parts = apiRepositoryURL.pathComponents
        guard
            let reposIndex = parts.firstIndex(of: "repos"),
            reposIndex + 2 < parts.count
        else {
            return nil
        }

        let owner = parts[reposIndex + 1]
        let repository = parts[reposIndex + 2]
        return "\(owner)/\(repository)"
    }

    private func subjectWebURL(subjectURL: URL?, repositoryWebURL: URL, subjectType: String) -> URL {
        guard let subjectURL else {
            return fallbackWebURL(repositoryWebURL: repositoryWebURL, subjectType: subjectType)
        }

        let parts = subjectURL.pathComponents
        guard let reposIndex = parts.firstIndex(of: "repos"), reposIndex + 4 < parts.count else {
            return fallbackWebURL(repositoryWebURL: repositoryWebURL, subjectType: subjectType)
        }

        let owner = parts[reposIndex + 1]
        let repository = parts[reposIndex + 2]
        let kind = parts[reposIndex + 3]
        let value = parts[reposIndex + 4]

        switch kind {
        case "pulls":
            return URL(string: "https://github.com/\(owner)/\(repository)/pull/\(value)")!
        case "issues":
            return URL(string: "https://github.com/\(owner)/\(repository)/issues/\(value)")!
        case "commits":
            return URL(string: "https://github.com/\(owner)/\(repository)/commit/\(value)")!
        default:
            return fallbackWebURL(repositoryWebURL: repositoryWebURL, subjectType: subjectType)
        }
    }

    private func fallbackWebURL(repositoryWebURL: URL, subjectType: String) -> URL {
        switch subjectType {
        case "CheckSuite", "WorkflowRun", "Build":
            return repositoryWebURL.appending(path: "actions")
        default:
            return repositoryWebURL
        }
    }

    private static func parseRateLimit(from response: HTTPURLResponse) -> GitHubRateLimit? {
        guard
            let limit = headerInt("X-RateLimit-Limit", in: response),
            let remaining = headerInt("X-RateLimit-Remaining", in: response)
        else {
            return nil
        }

        let resetAt = headerInt("X-RateLimit-Reset", in: response)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }

        return GitHubRateLimit(
            limit: limit,
            remaining: remaining,
            resetAt: resetAt,
            pollIntervalHintSeconds: headerInt("X-Poll-Interval", in: response),
            retryAfterSeconds: headerInt("Retry-After", in: response)
        )
    }

    private static func headerInt(_ name: String, in response: HTTPURLResponse) -> Int? {
        let candidates = [name, name.lowercased()]

        for candidate in candidates {
            if let stringValue = response.value(forHTTPHeaderField: candidate),
                let value = Int(stringValue) {
                return value
            }
        }

        return nil
    }

    private static func headerString(_ name: String, in response: HTTPURLResponse) -> String? {
        let candidates = [name, name.lowercased()]

        for candidate in candidates {
            if let stringValue = response.value(forHTTPHeaderField: candidate),
                !stringValue.isEmpty {
                return stringValue
            }
        }

        return nil
    }
}

private actor GitHubRateLimitObserver {
    private var current: GitHubRateLimit?

    func record(_ sample: GitHubRateLimit) {
        if let current {
            self.current = current.merged(with: sample)
        } else {
            current = sample
        }
    }

    func snapshot() -> GitHubRateLimit? {
        current
    }
}

private struct GraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

private enum ConditionalRequestResult<Response> {
    case modified(value: Response, etag: String?)
    case notModified(etag: String?)
}

private struct GraphQLResponse<DataType: Decodable>: Decodable {
    let data: DataType?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private struct PullRequestFocusQueryVariables: Encodable {
    let owner: String
    let name: String
    let number: Int
}

private struct PullRequestFocusQueryData: Decodable {
    let repository: PullRequestFocusGraphQLRepository?
}

private struct PullRequestNodeIDQueryData: Decodable {
    let repository: PullRequestNodeIDRepository?
}

private struct PullRequestNodeIDRepository: Decodable {
    let pullRequest: PullRequestNodeIDPullRequest?
}

private struct PullRequestNodeIDPullRequest: Decodable {
    let id: String
}

private struct PullRequestFocusGraphQLRepository: Decodable {
    let viewerPermission: String?
    let mergeCommitAllowed: Bool
    let squashMergeAllowed: Bool
    let rebaseMergeAllowed: Bool
    let pullRequest: PullRequestFocusGraphQLPullRequest?
}

private struct PullRequestFocusGraphQLPullRequest: Decodable {
    let id: String
    let title: String
    let bodyHTML: String
    let url: URL
    let baseRefName: String
    let state: String
    let merged: Bool
    let isInMergeQueue: Bool
    let isDraft: Bool
    let reviewDecision: String?
    let mergeable: String?
    let viewerDidAuthor: Bool
    let headRefOID: String
    let mergeCommit: PullRequestFocusGraphQLMergeCommit?
    let reviewRequests: PullRequestFocusGraphQLReviewRequestConnection
    let author: PullRequestFocusGraphQLActor?
    let timelineItems: PullRequestFocusGraphQLConnection<PullRequestFocusGraphQLAssignedEvent>
    let reviewThreads: PullRequestFocusGraphQLConnection<PullRequestFocusGraphQLReviewThread>
    let reviews: PullRequestFocusGraphQLConnection<PullRequestFocusGraphQLReview>
    let commits: PullRequestFocusGraphQLConnection<PullRequestFocusGraphQLCommitNode>

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case bodyHTML
        case url
        case baseRefName
        case state
        case merged
        case isInMergeQueue
        case isDraft
        case reviewDecision
        case mergeable
        case viewerDidAuthor
        case headRefOID = "headRefOid"
        case mergeCommit
        case reviewRequests
        case author
        case timelineItems
        case reviewThreads
        case reviews
        case commits
    }
}

private struct PullRequestFocusGraphQLMergeCommit: Decodable {
    let oid: String
}

private struct EnqueuePullRequestMutationVariables: Encodable {
    let pullRequestID: String

    enum CodingKeys: String, CodingKey {
        case pullRequestID = "pullRequestId"
    }
}

private struct EnqueuePullRequestMutationData: Decodable {
    let enqueuePullRequest: EnqueuePullRequestPayload?
}

private struct EnqueuePullRequestPayload: Decodable {
    let mergeQueueEntry: EnqueuePullRequestQueueEntry?
}

private struct EnqueuePullRequestQueueEntry: Decodable {
    let id: String
}

private struct PullRequestFocusGraphQLReviewRequestConnection: Decodable {
    let totalCount: Int
}

private struct PullRequestFocusGraphQLConnection<Node: Decodable>: Decodable {
    let nodes: [Node?]
}

private struct PullRequestFocusGraphQLActor: Decodable {
    let typeName: String
    let login: String
    let avatarURL: URL?
    let url: URL?

    enum CodingKeys: String, CodingKey {
        case typeName = "__typename"
        case login
        case avatarURL = "avatarUrl"
        case url
    }

    var isBotAccount: Bool {
        typeName == "Bot"
    }
}

private struct PullRequestFocusGraphQLReviewThread: Decodable {
    let id: String
    let isResolved: Bool
    let isOutdated: Bool
    let path: String?
    let line: Int?
    let startLine: Int?
    let comments: PullRequestFocusGraphQLConnection<PullRequestFocusGraphQLReviewComment>
}

private struct PullRequestFocusGraphQLAssignedEvent: Decodable {
    let typeName: String
    let createdAt: Date
    let actor: PullRequestFocusGraphQLActor?
    let assignee: PullRequestFocusGraphQLActor?

    enum CodingKeys: String, CodingKey {
        case typeName = "__typename"
        case createdAt
        case actor
        case assignee
    }
}

private struct PullRequestFocusGraphQLReviewComment: Decodable {
    let id: String
    let body: String
    let createdAt: Date
    let url: URL
    let outdated: Bool
    let viewerDidAuthor: Bool
    let author: PullRequestFocusGraphQLActor?
}

private struct PullRequestFocusGraphQLReview: Decodable {
    let state: String
    let submittedAt: Date
    let url: URL
    let author: PullRequestFocusGraphQLActor?
}

private struct PullRequestFocusGraphQLCommitNode: Decodable {
    let commit: PullRequestFocusGraphQLCommit
}

private struct PullRequestFocusGraphQLCommit: Decodable {
    let oid: String
    let abbreviatedOID: String
    let messageHeadline: String
    let committedDate: Date
    let url: URL
    let author: PullRequestFocusGraphQLCommitAuthor?

    enum CodingKeys: String, CodingKey {
        case oid
        case abbreviatedOID = "abbreviatedOid"
        case messageHeadline
        case committedDate
        case url
        case author
    }
}

private struct PullRequestFocusGraphQLCommitAuthor: Decodable {
    let user: PullRequestFocusGraphQLActor?
}

private struct PullRequestFocusThread {
    let isResolved: Bool
    let isOutdated: Bool
    let latestActivityAt: Date
    let entry: PullRequestFocusEntry
}

private struct PullRequestCheckInsights {
    let summary: PullRequestCheckSummary
    let failingEntries: [PullRequestFocusEntry]
}

private struct CheckRunsResponse: Decodable {
    let checkRuns: [CheckRun]

    enum CodingKeys: String, CodingKey {
        case checkRuns = "check_runs"
    }
}

private struct CheckRun: Decodable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let htmlURL: URL?
    let detailsURL: URL?
    let startedAt: Date?
    let completedAt: Date?
    let app: CheckRunApp?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case conclusion
        case htmlURL = "html_url"
        case detailsURL = "details_url"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case app
    }
}

private struct CheckRunApp: Decodable {
    let slug: String?
}

private struct PullRequestReviewSubmissionRequest: Encodable {
    let event: String
}

private struct PullRequestReviewSubmissionResponse: Decodable {
    let id: Int?
}

private struct PullRequestMergeRequest: Encodable {
    let mergeMethod: String

    enum CodingKeys: String, CodingKey {
        case mergeMethod = "merge_method"
    }
}

private struct PullRequestMergeResponse: Decodable {
    let sha: String?
    let merged: Bool
    let message: String
}

private struct RepositoryMergeSettingsResponse: Decodable {
    let allowMergeCommit: Bool
    let allowSquashMerge: Bool
    let allowRebaseMerge: Bool

    enum CodingKeys: String, CodingKey {
        case allowMergeCommit = "allow_merge_commit"
        case allowSquashMerge = "allow_squash_merge"
        case allowRebaseMerge = "allow_rebase_merge"
    }
}

private struct CurrentUser: Decodable {
    let login: String
}

private struct SearchIssuesResponse: Decodable {
    let items: [IssueItem]
}

private struct RepositoryIdentifier: Hashable, Sendable {
    let owner: String
    let name: String
}

private enum DiscussionKind: Hashable, Sendable {
    case issue
    case pullRequest
}

private struct DiscussionReference: Hashable, Sendable {
    let owner: String
    let name: String
    let number: Int
    let kind: DiscussionKind
}

private enum WorkflowWatchRelationship: Hashable, Sendable {
    case authored
    case approved
    case merged

    var priority: Int {
        switch self {
        case .authored:
            return 1
        case .approved:
            return 2
        case .merged:
            return 3
        }
    }
}

private struct WorkflowWatchCandidate: Hashable, Sendable {
    let repository: String
    let number: Int
    let relationship: WorkflowWatchRelationship
}

private struct TimelineContext: Hashable, Sendable {
    let event: String
    let reviewState: String?
    let actor: AttentionActor?
    let timestamp: Date
    let followUpRelationship: NotificationFollowUpRelationship?
    let stateTransition: PullRequestStateTransition?
    let detailEvidence: [AttentionEvidence]
}

private struct IssueItem: Decodable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: URL
    let repositoryURL: URL
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlURL = "html_url"
        case repositoryURL = "repository_url"
        case updatedAt = "updated_at"
    }
}

private struct PullRequestDetails: Decodable {
    let title: String
    let htmlURL: URL
    let state: String
    let isDraft: Bool
    let merged: Bool
    let mergedAt: Date?
    let mergeCommitSHA: String?
    let mergeable: Bool?
    let mergeableState: String?
    let requestedReviewers: [GitHubUser]
    let requestedTeams: [GitHubTeam]
    let head: PullRequestBranch

    enum CodingKeys: String, CodingKey {
        case title
        case htmlURL = "html_url"
        case state
        case isDraft = "draft"
        case merged
        case mergedAt = "merged_at"
        case mergeCommitSHA = "merge_commit_sha"
        case mergeable
        case mergeableState = "mergeable_state"
        case requestedReviewers = "requested_reviewers"
        case requestedTeams = "requested_teams"
        case head
    }
}

private struct PullRequestBranch: Decodable {
    let sha: String
}

private struct PullRequestStateResponse: Decodable {
    let state: String
    let merged: Bool
    let closedAt: Date?
    let mergedAt: Date?
    let mergeCommitSHA: String?
    let assignees: [GitHubUser]?

    enum CodingKeys: String, CodingKey {
        case state
        case merged
        case closedAt = "closed_at"
        case mergedAt = "merged_at"
        case mergeCommitSHA = "merge_commit_sha"
        case assignees
    }
}

private struct IssueStateResponse: Decodable {
    let state: String
    let closedAt: Date?

    enum CodingKeys: String, CodingKey {
        case state
        case closedAt = "closed_at"
    }
}

private struct PullRequestReview: Decodable {
    let state: String
    let user: GitHubUser
    let submittedAt: Date

    enum CodingKeys: String, CodingKey {
        case state
        case user
        case submittedAt = "submitted_at"
    }
}

private struct LatestApprovalSummary {
    let approvalCount: Int
    let hasChangesRequested: Bool
    let latestApprover: AttentionActor?
}

private struct GitHubUser: Decodable {
    let login: String
    let avatarURL: URL?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
    }
}

private struct NotificationThread: Decodable {
    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository

    enum CodingKeys: String, CodingKey {
        case id
        case unread
        case reason
        case updatedAt = "updated_at"
        case subject
        case repository
    }
}

private struct NotificationThreadCandidate: Sendable {
    let thread: NotificationThread
    let page: Int
}

private struct NotificationThreadScan: Sendable {
    let candidates: [NotificationThreadCandidate]
}

private struct FallbackNotificationCandidate: Sendable {
    let thread: NotificationThread
    let reviewTarget: ReviewRequestTarget?
}

private struct NotificationFetchResult: Sendable {
    let notifications: [NotificationSummary]
    let scanState: NotificationScanState
}

private struct Subject: Decodable {
    let title: String
    let type: String
    let url: URL?
}

private struct Repository: Decodable {
    let fullName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case htmlURL = "html_url"
    }
}

private enum ReviewRequestTarget: Hashable, Sendable {
    case direct
    case team(owner: String, slug: String?, name: String?)

    var isTeam: Bool {
        switch self {
        case .direct:
            return false
        case .team:
            return true
        }
    }

    func matches(owner: String, slug: String) -> Bool {
        switch self {
        case .direct:
            return false
        case let .team(targetOwner, targetSlug, _):
            guard let targetSlug else {
                return false
            }

            return targetOwner.caseInsensitiveCompare(owner) == .orderedSame &&
                targetSlug.caseInsensitiveCompare(slug) == .orderedSame
        }
    }
}

private struct RequestedReviewersResponse: Decodable {
    let users: [GitHubUser]
    let teams: [GitHubTeam]
}

private struct GitHubTeam: Decodable {
    let slug: String
    let name: String?
    let organization: GitHubOrganization?
}

private struct GitHubOrganization: Decodable {
    let login: String
}

private struct TimelineIdentity: Decodable {
    let login: String?
    let avatarURL: URL?
    let url: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
        case url = "html_url"
    }
}

private struct TimelineEntry: Decodable {
    let id: Int?
    let event: String?
    let createdAt: Date?
    let submittedAt: Date?
    let actor: GitHubUser?
    let user: GitHubUser?
    let author: TimelineIdentity?
    let committer: TimelineIdentity?
    let assignee: GitHubUser?
    let requestedReviewer: GitHubUser?
    let requestedTeam: GitHubTeam?
    let sha: String?
    let commitID: String?
    let commitURL: URL?
    let htmlURL: URL?
    let message: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case createdAt = "created_at"
        case submittedAt = "submitted_at"
        case actor
        case user
        case author
        case committer
        case assignee
        case requestedReviewer = "requested_reviewer"
        case requestedTeam = "requested_team"
        case sha
        case commitID = "commit_id"
        case commitURL = "commit_url"
        case htmlURL = "html_url"
        case message
        case state
    }
}

private struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

private struct WorkflowRun: Decodable {
    let id: Int
    let workflowID: Int?
    let name: String?
    let displayTitle: String?
    let htmlURL: URL?
    let event: String
    let status: String?
    let conclusion: String?
    let createdAt: Date
    let actor: GitHubUser?
    let triggeringActor: GitHubUser?

    enum CodingKeys: String, CodingKey {
        case id
        case workflowID = "workflow_id"
        case name
        case displayTitle = "display_title"
        case htmlURL = "html_url"
        case event
        case status
        case conclusion
        case createdAt = "created_at"
        case actor
        case triggeringActor = "triggering_actor"
    }
}

private struct RepositoryWorkflowsResponse: Decodable {
    let workflows: [RepositoryWorkflow]
}

private struct RepositoryWorkflow: Decodable {
    let id: Int
    let name: String
    let path: String
    let state: String
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case state
        case htmlURL = "html_url"
    }
}

private struct RepositoryContentFile: Decodable {
    let type: String
    let content: String?
    let encoding: String?
}

private struct PullRequestFile: Decodable {
    let filename: String
}

private struct PredictedPostMergeWorkflowSet {
    let workflows: [PredictedPostMergeWorkflow]
    let isBestEffort: Bool
}

private struct PredictedPostMergeWorkflow {
    let id: Int
    let title: String
    let url: URL
}

private enum PredictedPostMergeWorkflowOutcome {
    case matched(PredictedPostMergeWorkflow)
    case bestEffortOnly
    case ignored
}

private struct GitHubAPIError: Decodable {
    let message: String
}

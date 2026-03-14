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
    private let notificationPageSize = 50
    private let notificationPageLimit = 2
    private let actionableNotificationLimit = 24
    private let notificationEnrichmentLimit = 10
    private let workflowCandidateLimit = 8
    private let workflowRunLimit = 20

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func validateToken(token: String) async throws -> String {
        let user: CurrentUser = try await request(path: "/user", token: token)

        do {
            let _: [NotificationThread] = try await request(
                path: "/notifications",
                queryItems: [
                    URLQueryItem(name: "all", value: "false"),
                    URLQueryItem(name: "participating", value: "true"),
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

    func fetchSnapshot(token: String, preferredLogin: String?) async throws -> GitHubSnapshot {
        let observer = GitHubRateLimitObserver()
        let login = try await resolveLogin(
            token: token,
            preferredLogin: preferredLogin,
            observer: observer
        )

        async let pullRequestsTask = fetchAssignedPullRequests(
            token: token,
            login: login,
            observer: observer
        )
        async let notificationsTask = fetchActionableNotifications(
            token: token,
            login: login,
            observer: observer
        )
        async let workflowRunsTask = fetchWatchedWorkflowRuns(
            token: token,
            login: login,
            observer: observer
        )

        let pullRequests = try await pullRequestsTask
        let notifications = try await notificationsTask
        let workflowRuns = try await workflowRunsTask

        let attentionItems = buildAttentionItems(
            pullRequests: pullRequests,
            notifications: notifications,
            actionRuns: workflowRuns
        )

        return GitHubSnapshot(
            login: login,
            attentionItems: attentionItems,
            rateLimit: await observer.snapshot()
        )
    }

    private func buildAttentionItems(
        pullRequests: [PullRequestSummary],
        notifications: [NotificationSummary],
        actionRuns: [ActionRunSummary]
    ) -> [AttentionItem] {
        let pullRequestItems = pullRequests.map { pullRequest in
            AttentionItem(
                id: "pr:\(pullRequest.id)",
                ignoreKey: pullRequest.ignoreKey,
                type: .assignedPullRequest,
                title: pullRequest.title,
                subtitle: pullRequest.subtitle,
                timestamp: pullRequest.updatedAt,
                url: pullRequest.url
            )
        }

        let notificationItems = notifications.map { notification in
            AttentionItem(
                id: "notif:\(notification.id)",
                ignoreKey: notification.ignoreKey,
                type: notification.type,
                title: notification.title,
                subtitle: notification.subtitle,
                timestamp: notification.updatedAt,
                url: notification.url,
                actor: notification.actor,
                isUnread: notification.unread
            )
        }

        let actionRunItems = actionRuns.map { run in
            AttentionItem(
                id: "run:\(run.id)",
                ignoreKey: run.ignoreKey,
                type: run.type,
                title: run.title,
                subtitle: run.subtitle,
                timestamp: run.createdAt,
                url: run.url,
                actor: run.actor
            )
        }

        return (pullRequestItems + notificationItems + actionRunItems)
            .sorted { $0.timestamp > $1.timestamp }
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

    private func fetchAssignedPullRequests(
        token: String,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [PullRequestSummary] {
        let query = "is:open is:pr assignee:\(login) archived:false"

        let response: SearchIssuesResponse = try await request(
            path: "/search/issues",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "per_page", value: "20")
            ],
            token: token,
            observer: observer
        )

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
                updatedAt: issue.updatedAt
            )
        }
    }

    private func fetchActionableNotifications(
        token: String,
        login: String,
        observer: GitHubRateLimitObserver
    ) async throws -> [NotificationSummary] {
        let actionableReasons: Set<String> = [
            "assign",
            "author",
            "comment",
            "manual",
            "mention",
            "review_requested",
            "security_alert",
            "state_change",
            "subscribed",
            "team_mention"
        ]

        let candidateThreads = try await fetchNotificationThreads(
            token: token,
            actionableReasons: actionableReasons,
            observer: observer
        )

        let enrichedThreads = Array(candidateThreads.prefix(notificationEnrichmentLimit))
        let fallbackThreads = Array(candidateThreads.dropFirst(notificationEnrichmentLimit))

        let fallbackSummaries = fallbackThreads.map(buildFallbackNotificationSummary)

        return await withTaskGroup(of: NotificationSummary?.self) { group in
            for thread in enrichedThreads {
                group.addTask {
                    do {
                        return try await buildNotificationSummary(
                            token: token,
                            login: login,
                            thread: thread,
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

            return items.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func fetchNotificationThreads(
        token: String,
        actionableReasons: Set<String>,
        observer: GitHubRateLimitObserver
    ) async throws -> [NotificationThread] {
        var candidateThreads: [NotificationThread] = []

        for page in 1...notificationPageLimit {
            let threads: [NotificationThread] = try await request(
                path: "/notifications",
                queryItems: [
                    URLQueryItem(name: "all", value: "false"),
                    URLQueryItem(name: "participating", value: "true"),
                    URLQueryItem(name: "per_page", value: "\(notificationPageSize)"),
                    URLQueryItem(name: "page", value: "\(page)")
                ],
                token: token,
                observer: observer
            )

            candidateThreads.append(
                contentsOf: threads.filter { actionableReasons.contains($0.reason) }
            )

            if threads.count < notificationPageSize ||
                candidateThreads.count >= actionableNotificationLimit {
                break
            }
        }

        return Array(candidateThreads.prefix(actionableNotificationLimit))
    }

    private func buildNotificationSummary(
        token: String,
        login: String,
        thread: NotificationThread,
        observer: GitHubRateLimitObserver
    ) async throws -> NotificationSummary? {
        var actor: AttentionActor?
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
            }

            if let timelineContext = try await fetchTimelineContext(
                token: token,
                reference: reference,
                currentLogin: login,
                observer: observer
            ) {
                actor = timelineContext.actor
                type = AttentionItemType.notificationType(
                    reason: thread.reason,
                    timelineEvent: timelineContext.event,
                    reviewState: timelineContext.reviewState
                )
            }
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
            subtitle: notificationSubtitle(type: type, repository: repository, actor: actor),
            repository: repository,
            url: url,
            updatedAt: thread.updatedAt,
            unread: thread.unread,
            actor: actor
        )
    }

    private func buildFallbackNotificationSummary(thread: NotificationThread) -> NotificationSummary {
        let type = AttentionItemType.notificationType(
            reason: thread.reason,
            timelineEvent: nil,
            reviewState: nil
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
            subtitle: notificationSubtitle(type: type, repository: repository, actor: nil),
            repository: repository,
            url: url,
            updatedAt: thread.updatedAt,
            unread: thread.unread,
            actor: nil
        )
    }

    private func fetchTimelineContext(
        token: String,
        reference: DiscussionReference,
        currentLogin: String,
        observer: GitHubRateLimitObserver
    ) async throws -> TimelineContext? {
        let timeline: [TimelineEntry] = try await request(
            path: "/repos/\(reference.owner)/\(reference.name)/issues/\(reference.number)/timeline",
            queryItems: [
                URLQueryItem(name: "per_page", value: "20")
            ],
            token: token,
            observer: observer
        )

        let relevantEntries = timeline.compactMap { entry -> TimelineContext? in
            let event = (entry.event ?? "").lowercased()
            let actor = entry.actor ?? entry.user
            let timestamp = entry.submittedAt ?? entry.createdAt
            guard let timestamp else {
                return nil
            }

            guard !event.isEmpty else {
                return nil
            }

            guard actor?.login != currentLogin else {
                return nil
            }

            switch event {
            case "assigned",
                "closed",
                "commented",
                "committed",
                "head_ref_force_pushed",
                "merged",
                "reopened",
                "review_requested",
                "reviewed":
                return TimelineContext(
                    event: event,
                    reviewState: entry.state,
                    actor: attentionActor(from: actor),
                    timestamp: timestamp
                )
            default:
                return nil
            }
        }

        return relevantEntries.sorted { $0.timestamp > $1.timestamp }.first
    }

    private func notificationSubtitle(
        type: AttentionItemType,
        repository: String,
        actor: AttentionActor?
    ) -> String {
        if let actor {
            return "\(actor.login) · \(repository) · \(type.accessibilityLabel)"
        }

        return "\(repository) · \(type.accessibilityLabel)"
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
        let repositoryID = try parseRepositoryFullName(repository)
        let reviews: [PullRequestReview] = try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/pulls/\(number)/reviews",
            queryItems: [
                URLQueryItem(name: "per_page", value: "100")
            ],
            token: token,
            observer: observer
        )

        return reviews.contains {
            $0.user.login.caseInsensitiveCompare(login) == .orderedSame &&
                $0.state.caseInsensitiveCompare("APPROVED") == .orderedSame
        }
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

    private func attentionActor(from user: GitHubUser?) -> AttentionActor? {
        guard let user else {
            return nil
        }

        return AttentionActor(login: user.login, avatarURL: user.avatarURL)
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

    private func perform(
        _ request: URLRequest,
        observer: GitHubRateLimitObserver? = nil
    ) async throws -> Data {
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

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(GitHubAPIError.self, from: data).message) ?? "Unknown error"
            if http.statusCode == 403 || http.statusCode == 429 {
                let lowercasedMessage = message.lowercased()
                if lowercasedMessage.contains("rate limit") || rateLimit?.isExhausted == true {
                    throw GitHubClientError.rateLimited(rateLimit)
                }
            }
            throw GitHubClientError.api(statusCode: http.statusCode, message: message)
        }

        return data
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
    let merged: Bool
    let mergedAt: Date?
    let mergeCommitSHA: String?
    let head: PullRequestBranch

    enum CodingKeys: String, CodingKey {
        case title
        case htmlURL = "html_url"
        case state
        case merged
        case mergedAt = "merged_at"
        case mergeCommitSHA = "merge_commit_sha"
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

    enum CodingKeys: String, CodingKey {
        case state
        case merged
        case closedAt = "closed_at"
    }
}

private struct PullRequestReview: Decodable {
    let state: String
    let user: GitHubUser
}

private struct GitHubUser: Decodable {
    let login: String
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
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

private struct TimelineEntry: Decodable {
    let event: String?
    let createdAt: Date?
    let submittedAt: Date?
    let actor: GitHubUser?
    let user: GitHubUser?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case event
        case createdAt = "created_at"
        case submittedAt = "submitted_at"
        case actor
        case user
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

private struct GitHubAPIError: Decodable {
    let message: String
}

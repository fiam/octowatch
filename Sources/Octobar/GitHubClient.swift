import Foundation

enum GitHubClientError: LocalizedError {
    case invalidResponse
    case api(statusCode: Int, message: String)
    case unsupportedRepositoryName(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub API returned an invalid response."
        case let .api(statusCode, message):
            return "GitHub API error \(statusCode): \(message)"
        case let .unsupportedRepositoryName(name):
            return "Unsupported repository name format: \(name)"
        }
    }
}

struct GitHubClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let baseURL = URL(string: "https://api.github.com")!
    private let trackedMergedPullRequestsLimit = 12
    private let watchedRunLimit = 30
    private let failedRunConclusions: Set<String> = [
        "action_required",
        "failure",
        "timed_out",
        "startup_failure"
    ]

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchSnapshot(token: String, preferredLogin: String?) async throws -> GitHubSnapshot {
        let login = try await resolveLogin(token: token, preferredLogin: preferredLogin)

        async let pullRequestsTask = fetchAssignedPullRequests(token: token, login: login)
        async let notificationsTask = fetchActionableNotifications(token: token)

        let pullRequests = try await pullRequestsTask
        let notifications = try await notificationsTask

        let repositories = Set(
            pullRequests.map(\PullRequestSummary.repository)
            + notifications.map(\NotificationSummary.repository)
        )
        let actionRuns = try await fetchActionRequiredRuns(token: token, actor: login, repositories: Array(repositories))
        let attentionItems = buildAttentionItems(
            pullRequests: pullRequests,
            notifications: notifications,
            actionRuns: actionRuns
        )

        return GitHubSnapshot(
            login: login,
            attentionItems: attentionItems
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
                type: .assignedPullRequest,
                title: pullRequest.title,
                subtitle: "#\(pullRequest.number) · \(pullRequest.repository)",
                timestamp: pullRequest.updatedAt,
                url: pullRequest.url
            )
        }

        let notificationItems = notifications.map { notification in
            AttentionItem(
                id: "notif:\(notification.id)",
                type: .actionableNotification,
                title: notification.title,
                subtitle: "\(notification.repository) · \(humanized(reason: notification.reason))",
                timestamp: notification.updatedAt,
                url: notification.url
            )
        }

        let actionRunItems = actionRuns.map { run in
            AttentionItem(
                id: "run:\(run.id)",
                type: .actionRequiredRun,
                title: run.title,
                subtitle: "\(run.repository) · \(run.status) · \(run.event)",
                timestamp: run.createdAt,
                url: run.url
            )
        }

        return (pullRequestItems + notificationItems + actionRunItems)
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func humanized(reason: String) -> String {
        reason.replacingOccurrences(of: "_", with: " ")
    }

    private func resolveLogin(token: String, preferredLogin: String?) async throws -> String {
        if let preferredLogin, !preferredLogin.isEmpty {
            return preferredLogin
        }

        let user: CurrentUser = try await request(path: "/user", token: token)
        return user.login
    }

    private func fetchAssignedPullRequests(token: String, login: String) async throws -> [PullRequestSummary] {
        let query = "is:open is:pr assignee:\(login) archived:false"

        let response: SearchIssuesResponse = try await request(
            path: "/search/issues",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "per_page", value: "20")
            ],
            token: token
        )

        return response.items.compactMap { issue in
            guard let repository = repositoryFullName(from: issue.repositoryURL) else {
                return nil
            }

            return PullRequestSummary(
                id: issue.id,
                number: issue.number,
                title: issue.title,
                repository: repository,
                url: issue.htmlURL,
                updatedAt: issue.updatedAt
            )
        }
    }

    private func fetchActionableNotifications(token: String) async throws -> [NotificationSummary] {
        let threads: [NotificationThread] = try await request(
            path: "/notifications",
            queryItems: [
                URLQueryItem(name: "all", value: "false"),
                URLQueryItem(name: "participating", value: "true"),
                URLQueryItem(name: "per_page", value: "30")
            ],
            token: token
        )

        let actionableReasons: Set<String> = [
            "assign",
            "mention",
            "team_mention",
            "review_requested",
            "ci_activity",
            "security_alert",
            "state_change",
            "manual"
        ]

        let candidateThreads = threads.filter { actionableReasons.contains($0.reason) }

        return await withTaskGroup(of: NotificationSummary?.self) { group in
            for thread in candidateThreads {
                group.addTask {
                    do {
                        if let pullRequestReference = pullRequestReference(from: thread.subject.url) {
                            let isOpen = try await isPullRequestOpen(
                                token: token,
                                reference: pullRequestReference
                            )
                            if !isOpen {
                                return nil
                            }
                        }

                        return NotificationSummary(
                            id: thread.id,
                            title: thread.subject.title,
                            reason: thread.reason,
                            repository: thread.repository.fullName,
                            url: subjectWebURL(
                                subjectURL: thread.subject.url,
                                repositoryWebURL: thread.repository.htmlURL,
                                subjectType: thread.subject.type
                            ),
                            updatedAt: thread.updatedAt
                        )
                    } catch {
                        return nil
                    }
                }
            }

            var items: [NotificationSummary] = []
            for await item in group {
                if let item {
                    items.append(item)
                }
            }

            return items.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func pullRequestReference(from subjectURL: URL?) -> PullRequestReference? {
        guard let subjectURL else {
            return nil
        }

        let parts = subjectURL.pathComponents
        guard
            let reposIndex = parts.firstIndex(of: "repos"),
            reposIndex + 4 < parts.count,
            parts[reposIndex + 3] == "pulls",
            let number = Int(parts[reposIndex + 4])
        else {
            return nil
        }

        return PullRequestReference(
            owner: parts[reposIndex + 1],
            name: parts[reposIndex + 2],
            number: number
        )
    }

    private func isPullRequestOpen(token: String, reference: PullRequestReference) async throws -> Bool {
        let pullRequest: PullRequestStateResponse = try await request(
            path: "/repos/\(reference.owner)/\(reference.name)/pulls/\(reference.number)",
            token: token
        )

        return pullRequest.state == "open" && !pullRequest.merged
    }

    private func fetchPostMergeWatchItems(token: String, login: String) async throws -> [PostMergeWatchSummary] {
        async let reviewedByMeTask = fetchMergedPullRequestCandidates(
            token: token,
            query: "is:pr is:merged reviewed-by:\(login) archived:false"
        )
        async let authoredByMeTask = fetchMergedPullRequestCandidates(
            token: token,
            query: "is:pr is:merged author:\(login) archived:false"
        )

        let reviewedByMe = try await reviewedByMeTask
        let authoredByMe = try await authoredByMeTask

        var uniqueCandidates = [String: MergedPullRequestCandidate]()
        for candidate in reviewedByMe + authoredByMe {
            let key = "\(candidate.repository)#\(candidate.number)"
            if let existing = uniqueCandidates[key], existing.mergedAt >= candidate.mergedAt {
                continue
            }
            uniqueCandidates[key] = candidate
        }

        let candidates = uniqueCandidates.values
            .sorted { $0.mergedAt > $1.mergedAt }
            .prefix(trackedMergedPullRequestsLimit)

        return await withTaskGroup(of: PostMergeWatchSummary?.self) { group in
            for candidate in candidates {
                group.addTask {
                    do {
                        return try await buildPostMergeWatchSummary(token: token, candidate: candidate)
                    } catch {
                        return nil
                    }
                }
            }

            var results: [PostMergeWatchSummary] = []
            for await item in group {
                if let item {
                    results.append(item)
                }
            }

            return results.sorted { $0.mergedAt > $1.mergedAt }
        }
    }

    private func fetchMergedPullRequestCandidates(token: String, query: String) async throws -> [MergedPullRequestCandidate] {
        let response: SearchIssuesResponse = try await request(
            path: "/search/issues",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "per_page", value: "\(trackedMergedPullRequestsLimit)")
            ],
            token: token
        )

        return response.items.compactMap { issue in
            guard
                let repository = repositoryFullName(from: issue.repositoryURL),
                let mergedAt = issue.pullRequest?.mergedAt
            else {
                return nil
            }

            return MergedPullRequestCandidate(
                repository: repository,
                number: issue.number,
                mergedAt: mergedAt
            )
        }
    }

    private func buildPostMergeWatchSummary(token: String, candidate: MergedPullRequestCandidate) async throws -> PostMergeWatchSummary? {
        let repositoryID = try parseRepositoryFullName(candidate.repository)

        let pullRequest: PullRequestDetails = try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/pulls/\(candidate.number)",
            token: token
        )

        guard
            pullRequest.merged,
            let mergedAt = pullRequest.mergedAt,
            let mergeCommitSHA = pullRequest.mergeCommitSHA,
            !mergeCommitSHA.isEmpty
        else {
            return nil
        }

        let runs = try await fetchWorkflowRunsForCommit(
            token: token,
            repository: candidate.repository,
            mergeCommitSHA: mergeCommitSHA
        )

        let status = postMergeWorkflowStatus(from: runs)

        let failedRuns = runs
            .filter(isFailedWorkflowRun)
            .map { run in
                PostMergeFailedRun(
                    name: run.name ?? "Workflow run",
                    conclusion: run.conclusion ?? "failure",
                    url: run.htmlURL ?? runWebURL(repository: candidate.repository, runID: run.id)
                )
            }

        let latestRunURL = runs
            .sorted { $0.createdAt > $1.createdAt }
            .first
            .map { run in
                run.htmlURL ?? runWebURL(repository: candidate.repository, runID: run.id)
            }

        return PostMergeWatchSummary(
            id: "\(candidate.repository)#\(candidate.number)",
            number: candidate.number,
            title: pullRequest.title,
            repository: candidate.repository,
            prURL: pullRequest.htmlURL,
            mergedAt: mergedAt,
            mergeCommitSHA: mergeCommitSHA,
            status: status,
            totalRuns: runs.count,
            failedRuns: failedRuns,
            latestRunURL: latestRunURL
        )
    }

    private func fetchWorkflowRunsForCommit(
        token: String,
        repository: String,
        mergeCommitSHA: String
    ) async throws -> [WorkflowRun] {
        let repositoryID = try parseRepositoryFullName(repository)
        let response: WorkflowRunsResponse = try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/actions/runs",
            queryItems: [
                URLQueryItem(name: "head_sha", value: mergeCommitSHA),
                URLQueryItem(name: "per_page", value: "\(watchedRunLimit)")
            ],
            token: token
        )

        return response.workflowRuns
    }

    private func postMergeWorkflowStatus(from runs: [WorkflowRun]) -> PostMergeWorkflowStatus {
        if runs.isEmpty {
            return .noRuns
        }

        if runs.contains(where: isFailedWorkflowRun) {
            return .failed
        }

        if runs.contains(where: isPendingWorkflowRun) {
            return .pending
        }

        return .succeeded
    }

    private func isPendingWorkflowRun(_ run: WorkflowRun) -> Bool {
        let status = (run.status ?? "").lowercased()
        if status != "completed" {
            return true
        }

        return run.conclusion == nil
    }

    private func isFailedWorkflowRun(_ run: WorkflowRun) -> Bool {
        let status = (run.status ?? "").lowercased()
        if status == "action_required" {
            return true
        }

        guard let conclusion = run.conclusion?.lowercased() else {
            return false
        }

        return failedRunConclusions.contains(conclusion)
    }

    private func fetchActionRequiredRuns(token: String, actor: String, repositories: [String]) async throws -> [ActionRunSummary] {
        let repositoriesToQuery = Array(repositories.sorted().prefix(10))

        return await withTaskGroup(of: [ActionRunSummary].self) { group in
            for repository in repositoriesToQuery {
                group.addTask {
                    do {
                        return try await fetchActionRequiredRuns(
                            token: token,
                            actor: actor,
                            repository: repository
                        )
                    } catch {
                        return []
                    }
                }
            }

            var allRuns: [ActionRunSummary] = []
            for await runs in group {
                allRuns.append(contentsOf: runs)
            }

            return allRuns.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func fetchActionRequiredRuns(token: String, actor: String, repository: String) async throws -> [ActionRunSummary] {
        let repositoryID = try parseRepositoryFullName(repository)

        let response: WorkflowRunsResponse = try await request(
            path: "/repos/\(repositoryID.owner)/\(repositoryID.name)/actions/runs",
            queryItems: [
                URLQueryItem(name: "actor", value: actor),
                URLQueryItem(name: "status", value: "action_required"),
                URLQueryItem(name: "per_page", value: "10")
            ],
            token: token
        )

        return response.workflowRuns.map { run in
            let fallbackURL = runWebURL(repository: repository, runID: run.id)

            return ActionRunSummary(
                id: "\(repository)-\(run.id)",
                title: run.name ?? "Workflow run",
                repository: repository,
                status: run.status ?? "unknown",
                event: run.event,
                createdAt: run.createdAt,
                url: run.htmlURL ?? fallbackURL
            )
        }
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
        token: String
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
        request.setValue("Octobar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(GitHubAPIError.self, from: data).message) ?? "Unknown error"
            throw GitHubClientError.api(statusCode: http.statusCode, message: message)
        }

        return try decoder.decode(Response.self, from: data)
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
}

private struct CurrentUser: Decodable {
    let login: String
}

private struct SearchIssuesResponse: Decodable {
    let items: [IssueItem]
}

private struct MergedPullRequestCandidate: Hashable, Sendable {
    let repository: String
    let number: Int
    let mergedAt: Date
}

private struct RepositoryIdentifier: Hashable, Sendable {
    let owner: String
    let name: String
}

private struct PullRequestReference: Hashable, Sendable {
    let owner: String
    let name: String
    let number: Int
}

private struct IssueItem: Decodable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: URL
    let repositoryURL: URL
    let updatedAt: Date
    let pullRequest: IssuePullRequest?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlURL = "html_url"
        case repositoryURL = "repository_url"
        case updatedAt = "updated_at"
        case pullRequest = "pull_request"
    }
}

private struct IssuePullRequest: Decodable {
    let mergedAt: Date?

    enum CodingKeys: String, CodingKey {
        case mergedAt = "merged_at"
    }
}

private struct PullRequestDetails: Decodable {
    let title: String
    let htmlURL: URL
    let merged: Bool
    let mergedAt: Date?
    let mergeCommitSHA: String?

    enum CodingKeys: String, CodingKey {
        case title
        case htmlURL = "html_url"
        case merged
        case mergedAt = "merged_at"
        case mergeCommitSHA = "merge_commit_sha"
    }
}

private struct PullRequestStateResponse: Decodable {
    let state: String
    let merged: Bool
}

private struct NotificationThread: Decodable {
    let id: String
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository

    enum CodingKeys: String, CodingKey {
        case id
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

private struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

private struct WorkflowRun: Decodable {
    let id: Int
    let name: String?
    let htmlURL: URL?
    let event: String
    let status: String?
    let conclusion: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case htmlURL = "html_url"
        case event
        case status
        case conclusion
        case createdAt = "created_at"
    }
}

private struct GitHubAPIError: Decodable {
    let message: String
}

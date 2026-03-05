import Foundation

struct PullRequestSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let repository: String
    let url: URL
    let updatedAt: Date
}

struct NotificationSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let reason: String
    let repository: String
    let url: URL
    let updatedAt: Date
}

struct ActionRunSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let repository: String
    let status: String
    let event: String
    let createdAt: Date
    let url: URL
}

enum PostMergeWorkflowStatus: String, Hashable, Sendable {
    case failed
    case pending
    case succeeded
    case noRuns

    var isActionable: Bool {
        self == .failed
    }

    var label: String {
        switch self {
        case .failed:
            return "failed"
        case .pending:
            return "running"
        case .succeeded:
            return "passed"
        case .noRuns:
            return "no runs"
        }
    }
}

struct PostMergeFailedRun: Hashable, Sendable {
    let name: String
    let conclusion: String
    let url: URL
}

struct PostMergeWatchSummary: Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let title: String
    let repository: String
    let prURL: URL
    let mergedAt: Date
    let mergeCommitSHA: String
    let status: PostMergeWorkflowStatus
    let totalRuns: Int
    let failedRuns: [PostMergeFailedRun]
    let latestRunURL: URL?

    var destinationURL: URL {
        failedRuns.first?.url ?? latestRunURL ?? prURL
    }
}

struct GitHubSnapshot: Sendable {
    let login: String
    let assignedPullRequests: [PullRequestSummary]
    let actionableNotifications: [NotificationSummary]
    let actionRequiredRuns: [ActionRunSummary]
    let postMergeWatchItems: [PostMergeWatchSummary]
}

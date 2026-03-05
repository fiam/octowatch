import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var assignedPullRequests: [PullRequestSummary] = []
    @Published private(set) var actionableNotifications: [NotificationSummary] = []
    @Published private(set) var actionRequiredRuns: [ActionRunSummary] = []
    @Published private(set) var postMergeWatchItems: [PostMergeWatchSummary] = []
    @Published private(set) var userLogin: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    @Published var tokenInput = ""
    @Published var pollingEnabled = true

    private let tokenAccount = "github-personal-access-token"
    private let keychain = KeychainStore(service: "dev.octobar.app")
    private let client = GitHubClient()
    private let notifier = UserNotifier()

    private var token: String?
    private var pollingTask: Task<Void, Never>?
    private var knownItemIDs = Set<String>()
    private var knownPostMergeFailureIDs = Set<String>()

    init() {
        token = keychain.read(account: tokenAccount)
        tokenInput = token ?? ""

        Task {
            await notifier.requestAuthorization()
        }

        if hasToken {
            startPollingIfNeeded()
        } else {
            Task { [weak self] in
                await self?.importTokenFromGitHubCLIIfAvailable()
            }
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    var hasToken: Bool {
        !(token ?? "").isEmpty
    }

    var actionableCount: Int {
        assignedPullRequests.count
            + actionableNotifications.count
            + actionRequiredRuns.count
            + postMergeFailureItems.count
    }

    var postMergeFailureItems: [PostMergeWatchSummary] {
        postMergeWatchItems.filter { $0.status.isActionable }
    }

    func saveToken() {
        let cleaned = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            clearToken()
            return
        }

        guard keychain.save(value: cleaned, account: tokenAccount) else {
            lastError = "Failed to save token in Keychain."
            return
        }

        token = cleaned
        knownItemIDs.removeAll()
        knownPostMergeFailureIDs.removeAll()
        lastError = nil

        startPollingIfNeeded()
        refreshNow()
    }

    func clearToken() {
        _ = keychain.delete(account: tokenAccount)

        token = nil
        tokenInput = ""
        assignedPullRequests = []
        actionableNotifications = []
        actionRequiredRuns = []
        postMergeWatchItems = []
        userLogin = nil
        lastUpdated = nil
        lastError = nil
        knownItemIDs.removeAll()
        knownPostMergeFailureIDs.removeAll()

        pollingTask?.cancel()
        pollingTask = nil
    }

    func setPollingEnabled(_ enabled: Bool) {
        pollingEnabled = enabled

        if enabled {
            startPollingIfNeeded()
            refreshNow()
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    func refreshNow() {
        Task {
            await refresh(force: true)
        }
    }

    private func startPollingIfNeeded() {
        guard hasToken, pollingEnabled else {
            return
        }

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refresh(force: true)

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled {
                    return
                }
                await self.refresh(force: false)
            }
        }
    }

    private func refresh(force: Bool) async {
        guard hasToken else {
            return
        }

        guard pollingEnabled || force else {
            return
        }

        guard let token else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = try await client.fetchSnapshot(token: token, preferredLogin: userLogin)
            userLogin = snapshot.login
            assignedPullRequests = snapshot.assignedPullRequests
            actionableNotifications = snapshot.actionableNotifications
            actionRequiredRuns = snapshot.actionRequiredRuns
            postMergeWatchItems = snapshot.postMergeWatchItems
            lastUpdated = Date()
            lastError = nil

            notifyIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func importTokenFromGitHubCLIIfAvailable() async {
        guard !hasToken else {
            return
        }

        guard let cliToken = await GitHubCLITokenProvider.fetchToken() else {
            return
        }

        tokenInput = cliToken
        saveToken()
    }

    private func notifyIfNeeded() {
        let currentIDs = Set(
            assignedPullRequests.map { "pr:\($0.id)" }
            + actionableNotifications.map { "notif:\($0.id)" }
            + actionRequiredRuns.map { "run:\($0.id)" }
        )
        let currentPostMergeFailureIDs = Set(
            postMergeFailureItems.map { "postmerge:\($0.id)" }
        )

        let newItems = currentIDs.subtracting(knownItemIDs)
        if !knownItemIDs.isEmpty, !newItems.isEmpty {
            let count = newItems.count
            let suffix = count == 1 ? "" : "s"
            notifier.notify(
                title: "Octobar",
                body: "\(count) new GitHub item\(suffix) need attention."
            )
        }

        let newFailedPostMergeItems = currentPostMergeFailureIDs.subtracting(knownPostMergeFailureIDs)
        if !knownPostMergeFailureIDs.isEmpty, !newFailedPostMergeItems.isEmpty {
            let count = newFailedPostMergeItems.count
            let suffix = count == 1 ? "" : "s"
            notifier.notify(
                title: "Octobar",
                body: "\(count) post-merge workflow\(suffix) failed."
            )
        }

        knownItemIDs = currentIDs
        knownPostMergeFailureIDs = currentPostMergeFailureIDs
    }
}

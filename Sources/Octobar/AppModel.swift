import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private enum TokenSource {
        case githubCLI
        case personalAccessToken
    }

    static let shared = AppModel()

    @Published private(set) var attentionItems: [AttentionItem] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var rateLimit: GitHubRateLimit?

    @Published var tokenInput = ""
    @Published private(set) var isResolvingInitialContent = true
    @Published private(set) var gitHubCLIAvailable = false
    @Published private(set) var usingGitHubCLIToken = false
    @Published private(set) var isValidatingToken = false
    @Published private(set) var ignoredItems: [IgnoredAttentionSubject] = []
    @Published private(set) var ignoreUndoState: IgnoreUndoState?
    @Published private(set) var pollIntervalSeconds = 60
    @Published private(set) var autoMarkReadSetting: AutoMarkReadSetting = .threeSeconds

    private let readStateStoreKey = "attention-item-read-state-v1"
    private let ignoredSubjectStoreKey = "ignored-attention-subjects-v2"
    private let legacyIgnoredSubjectStoreKey = "ignored-attention-subjects-v1"
    private let pollIntervalStoreKey = "poll-interval-seconds-v1"
    private let autoMarkReadStoreKey = "auto-mark-read-setting-v1"
    private let notificationScanStateStoreKey = "notification-scan-state-v1"
    private let teamMembershipStoreKey = "team-membership-cache-v1"
    private let client = GitHubClient()
    private let notifier = UserNotifier()
    private let pullRequestFocusCacheTTL: TimeInterval = 300

    private struct PullRequestFocusCacheEntry {
        let focus: PullRequestFocus
        let sourceTimestamp: Date
        let loadedAt: Date
    }

    private var token: String?
    private var userLogin: String?
    private var pollingTask: Task<Void, Never>?
    private var knownItemIDs = Set<String>()
    private var notificationScanState = NotificationScanState.default
    private var teamMembershipCache = TeamMembershipCache.default
    private var pullRequestFocusCache = [String: PullRequestFocusCacheEntry]()
    private var ignoredItemsByKey = [String: IgnoredAttentionSubject]()
    private var ignoreUndoDismissTask: Task<Void, Never>?
    private var readStateByItemID: [String: Date] = [:]
    private var suppressedTransitionNotificationKeys = Set<String>()
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    init() {
        gitHubCLIAvailable = GitHubCLITokenProvider.isInstalled
        pollIntervalSeconds = Self.loadPollInterval(
            from: UserDefaults.standard,
            key: pollIntervalStoreKey
        )
        autoMarkReadSetting = Self.loadAutoMarkReadSetting(
            from: UserDefaults.standard,
            key: autoMarkReadStoreKey
        )
        notificationScanState = Self.loadNotificationScanState(
            from: UserDefaults.standard,
            key: notificationScanStateStoreKey
        )
        teamMembershipCache = Self.loadTeamMembershipCache(
            from: UserDefaults.standard,
            key: teamMembershipStoreKey
        )
        readStateByItemID = Self.loadReadState(
            from: UserDefaults.standard,
            key: readStateStoreKey
        )
        ignoredItemsByKey = Self.loadIgnoredItems(
            from: UserDefaults.standard,
            key: ignoredSubjectStoreKey
        ) ?? Self.loadLegacyIgnoredItems(
            from: UserDefaults.standard,
            key: legacyIgnoredSubjectStoreKey
        )
        syncIgnoredItems()

        if let launchFixture = LaunchFixture.load(from: ProcessInfo.processInfo.environment) {
            applyLaunchFixture(launchFixture)
            return
        }

        Task {
            await notifier.requestAuthorization()
        }

        Task { [weak self] in
            await self?.bootstrapToken()
        }
    }

    deinit {
        pollingTask?.cancel()
        ignoreUndoDismissTask?.cancel()
    }

    var hasToken: Bool {
        !(token ?? "").isEmpty
    }

    var actionableCount: Int {
        attentionItems.count
    }

    var unreadCount: Int {
        attentionItems.filter { $0.isUnread }.count
    }

    var relativeLastUpdated: String {
        relativeLastUpdated(relativeTo: Date())
    }

    func relativeLastUpdated(relativeTo referenceDate: Date) -> String {
        guard let lastUpdated else {
            return "Not refreshed yet"
        }

        if abs(lastUpdated.timeIntervalSince(referenceDate)) < 1 {
            return "Updated now"
        }

        let relative = relativeDateFormatter.localizedString(
            for: lastUpdated,
            relativeTo: referenceDate
        )
        return "Updated \(relative)"
    }

    var pollIntervalOptions: [Int] {
        [30, 60, 120, 300, 600, 900]
    }

    var autoMarkReadOptions: [AutoMarkReadSetting] {
        AutoMarkReadSetting.allCases
    }

    var autoMarkReadDelay: Duration? {
        autoMarkReadSetting.delay
    }

    var isRateLimitWarning: Bool {
        rateLimit?.isLow == true || rateLimit?.isExhausted == true
    }

    func rateLimitSummary(relativeTo referenceDate: Date) -> String? {
        guard let rateLimit else {
            return nil
        }

        var segments = ["API \(rateLimit.remaining)/\(rateLimit.limit) left"]

        if let resetAt = rateLimit.resetAt {
            let resetDescription: String
            let resetDelta = resetAt.timeIntervalSince(referenceDate)
            if abs(resetDelta) < 1 {
                resetDescription = "resets now"
            } else if resetDelta > 1 {
                resetDescription = "resets \(relativeDateFormatter.localizedString(for: resetAt, relativeTo: referenceDate))"
            } else {
                resetDescription = ""
            }
            if !resetDescription.isEmpty {
                segments.append(resetDescription)
            }
        }

        if let pollIntervalHint = rateLimit.pollIntervalHintSeconds,
            pollIntervalHint > pollIntervalSeconds {
            segments.append("GitHub suggests \(pollIntervalHint)s polls")
        }

        let effectiveInterval = rateLimit.minimumAutomaticRefreshInterval(
            userConfiguredSeconds: pollIntervalSeconds,
            now: referenceDate
        )
        if effectiveInterval > pollIntervalSeconds {
            segments.append("polling every \(formatInterval(effectiveInterval))")
        }

        return segments.joined(separator: " · ")
    }

    func saveToken() async -> Bool {
        let cleaned = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            clearToken()
            return false
        }

        return await validateAndApplyToken(cleaned, source: .personalAccessToken)
    }

    func clearToken() {
        token = nil
        tokenInput = ""
        usingGitHubCLIToken = false
        attentionItems = []
        userLogin = nil
        lastUpdated = nil
        lastError = nil
        rateLimit = nil
        knownItemIDs.removeAll()
        notificationScanState = .default
        teamMembershipCache = .default
        pullRequestFocusCache = [:]
        suppressedTransitionNotificationKeys = []
        clearIgnoreUndoState()
        UserDefaults.standard.removeObject(forKey: notificationScanStateStoreKey)
        UserDefaults.standard.removeObject(forKey: teamMembershipStoreKey)

        pollingTask?.cancel()
        pollingTask = nil
    }

    func reloadTokenFromGitHubCLI() async -> Bool {
        await importTokenFromGitHubCLIIfAvailable(force: true)
    }

    func setPollIntervalSeconds(_ seconds: Int) {
        let normalized = Self.normalizedPollInterval(seconds)
        guard pollIntervalSeconds != normalized else {
            return
        }

        pollIntervalSeconds = normalized
        UserDefaults.standard.set(normalized, forKey: pollIntervalStoreKey)

        if hasToken {
            startPollingIfNeeded()
        }
    }

    func setAutoMarkReadSetting(_ setting: AutoMarkReadSetting) {
        guard autoMarkReadSetting != setting else {
            return
        }

        autoMarkReadSetting = setting
        UserDefaults.standard.set(setting.rawValue, forKey: autoMarkReadStoreKey)
    }

    func refreshNow() {
        guard hasToken, !isRefreshing else {
            return
        }

        Task {
            await refresh(force: true)
        }
    }

    func fetchPullRequestFocus(
        for item: AttentionItem,
        force: Bool = false
    ) async throws -> PullRequestFocus? {
        guard let reference = item.pullRequestReference else {
            return nil
        }

        guard let token, let userLogin else {
            return nil
        }

        let cacheKey = item.ignoreKey
        if
            !force,
            let cached = pullRequestFocusCache[cacheKey],
            cached.sourceTimestamp >= item.timestamp,
            Date().timeIntervalSince(cached.loadedAt) < pullRequestFocusCacheTTL
        {
            return cached.focus
        }

        let result = try await client.fetchPullRequestFocus(
            token: token,
            login: userLogin,
            reference: reference,
            sourceType: item.type
        )

        if let sample = result.rateLimit {
            if let current = rateLimit {
                rateLimit = current.merged(with: sample)
            } else {
                rateLimit = sample
            }
        }

        pullRequestFocusCache[cacheKey] = PullRequestFocusCacheEntry(
            focus: result.focus,
            sourceTimestamp: item.timestamp,
            loadedAt: Date()
        )

        return result.focus
    }

    func approveAndMergePullRequest(
        for item: AttentionItem,
        requiresApproval: Bool
    ) async throws {
        guard let reference = item.pullRequestReference, let token else {
            throw GitHubClientError.invalidResponse
        }

        let rateLimitSample = try await client.approveAndMergePullRequest(
            token: token,
            reference: reference,
            approveFirst: requiresApproval
        )

        if let rateLimitSample {
            if let current = rateLimit {
                rateLimit = current.merged(with: rateLimitSample)
            } else {
                rateLimit = rateLimitSample
            }
        }

        markItemAsRead(item)
        suppressedTransitionNotificationKeys.insert(item.ignoreKey)
        pullRequestFocusCache[item.ignoreKey] = nil
        await refresh(force: true)
    }

    func markItemAsRead(_ item: AttentionItem) {
        updateReadState(for: item, isUnread: false)
    }

    func toggleReadState(for item: AttentionItem) {
        updateReadState(for: item, isUnread: !item.isUnread)
    }

    func ignore(_ item: AttentionItem) {
        let summary = preferredIgnoredSummary(for: item)
        ignoredItemsByKey[item.ignoreKey] = summary
        syncIgnoredItems()
        persistIgnoredItems()
        presentIgnoreUndo(for: summary)

        attentionItems.removeAll { $0.ignoreKey == item.ignoreKey }
        knownItemIDs = Set(attentionItems.map(\.id))
    }

    func unignore(_ ignoredItem: IgnoredAttentionSubject) {
        ignoredItemsByKey[ignoredItem.ignoreKey] = nil
        syncIgnoredItems()
        persistIgnoredItems()

        if ignoreUndoState?.subject.ignoreKey == ignoredItem.ignoreKey {
            clearIgnoreUndoState()
        }

        if hasToken {
            refreshNow()
        }
    }

    func undoRecentIgnore() {
        guard let ignoreUndoState else {
            return
        }

        unignore(ignoreUndoState.subject)
        clearIgnoreUndoState()
    }

    func dismissIgnoreUndo() {
        clearIgnoreUndoState()
    }

    private func startPollingIfNeeded() {
        guard hasToken else {
            return
        }

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            if !self.shouldDelayAutomaticRefresh(relativeTo: .now) {
                await self.refresh(force: true)
            }

            while !Task.isCancelled {
                let interval = Double(self.effectiveAutomaticPollInterval(relativeTo: .now))
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled {
                    return
                }
                await self.refresh(force: false)
            }
        }
    }

    private func refresh(force: Bool) async {
        guard hasToken, !isRefreshing else {
            return
        }

        guard let token else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        if !force, shouldDelayAutomaticRefresh(relativeTo: .now) {
            return
        }

        let previousItems = attentionItems

        do {
            let snapshot = try await client.fetchSnapshot(
                token: token,
                preferredLogin: userLogin,
                notificationScanState: notificationScanState,
                teamMembershipCache: teamMembershipCache
            )
            userLogin = snapshot.login
            rateLimit = snapshot.rateLimit
            notificationScanState = snapshot.notificationScanState.normalized
            teamMembershipCache = snapshot.teamMembershipCache.normalized
            persistNotificationScanState()
            persistTeamMembershipCache()
            attentionItems = AttentionItemVisibilityPolicy
                .excludingIgnoredSubjects(
                    snapshot.attentionItems.map(applyingLocalReadState),
                    ignoredKeys: Set(ignoredItemsByKey.keys)
                )
            lastUpdated = Date()
            lastError = nil

            await notifyIfNeeded(previousItems: previousItems, token: token)
        } catch {
            if let clientError = error as? GitHubClientError,
                case let .rateLimited(rateLimit) = clientError {
                self.rateLimit = rateLimit
            }
            lastError = error.localizedDescription
        }

        if isResolvingInitialContent {
            isResolvingInitialContent = false
        }
    }

    private func bootstrapToken() async {
        let importedToken = await importTokenFromGitHubCLIIfAvailable(force: false)
        if !importedToken {
            isResolvingInitialContent = false
        }
    }

    private func importTokenFromGitHubCLIIfAvailable(force: Bool) async -> Bool {
        guard gitHubCLIAvailable else {
            if force {
                lastError = "GitHub CLI is not installed."
            }
            return false
        }

        if !force, hasToken {
            return true
        }

        guard let cliToken = await GitHubCLITokenProvider.fetchToken() else {
            if force {
                lastError = "Could not load token from `gh auth token`."
            }
            return false
        }

        return await validateAndApplyToken(cliToken, source: .githubCLI)
    }

    private func validateAndApplyToken(
        _ candidate: String,
        source: TokenSource
    ) async -> Bool {
        guard !isValidatingToken else {
            return false
        }

        isValidatingToken = true
        defer { isValidatingToken = false }

        do {
            let validatedLogin = try await client.validateToken(token: candidate)
            let previousLogin = userLogin

            token = candidate
            userLogin = validatedLogin
            usingGitHubCLIToken = source == .githubCLI
            tokenInput = source == .githubCLI ? "" : candidate
            knownItemIDs.removeAll()
            lastError = nil
            rateLimit = nil
            pullRequestFocusCache = [:]
            suppressedTransitionNotificationKeys = []

            if previousLogin?.caseInsensitiveCompare(validatedLogin) != .orderedSame {
                teamMembershipCache = .default
                UserDefaults.standard.removeObject(forKey: teamMembershipStoreKey)
            }

            startPollingIfNeeded()
            refreshNow()
            return true
        } catch {
            lastError = userFacingTokenError(for: error, source: source)
            return false
        }
    }

    private func userFacingTokenError(
        for error: Error,
        source: TokenSource
    ) -> String {
        if let clientError = error as? GitHubClientError {
            switch clientError {
            case .invalidCredentials:
                return "GitHub rejected that token. Check the token and try again."
            case .rateLimited:
                return "GitHub rate-limited the validation request. Try again in a few minutes."
            case let .tokenValidation(message):
                return message
            case let .api(statusCode, message):
                return "GitHub API error \(statusCode): \(message)"
            default:
                break
            }
        }

        if source == .githubCLI {
            return """
            GitHub CLI is available, but its token cannot be used with Octowatch. \
            Provide a GitHub token with access to notifications and pull request search.
            """
        }

        return "That token could not be validated for Octowatch."
    }

    private func notifyIfNeeded(previousItems: [AttentionItem], token: String) async {
        let currentIDs = Set(attentionItems.map(\.id))
        let newItems = attentionItems
            .filter { currentIDs.contains($0.id) && !knownItemIDs.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }

        if !knownItemIDs.isEmpty {
            for item in newItems.prefix(5) {
                notifier.notify(item: item)
            }

            let removedItems = previousItems.filter { knownItemIDs.contains($0.id) && !currentIDs.contains($0.id) }
            let groupedRemovedItems = Dictionary(grouping: removedItems, by: \.ignoreKey)
            let sortedRemovedGroups = groupedRemovedItems.values.sorted { lhs, rhs in
                let lhsTimestamp = lhs.map(\.timestamp).max() ?? .distantPast
                let rhsTimestamp = rhs.map(\.timestamp).max() ?? .distantPast
                return lhsTimestamp > rhsTimestamp
            }

            var deliveredTransitionNotifications = 0
            for removedGroup in sortedRemovedGroups {
                guard deliveredTransitionNotifications < 3 else {
                    break
                }

                guard let ignoreKey = removedGroup.first?.ignoreKey else {
                    continue
                }

                if suppressedTransitionNotificationKeys.remove(ignoreKey) != nil {
                    continue
                }

                guard
                    let representative = removedGroup.max(by: { $0.timestamp < $1.timestamp }),
                    let subjectReference = representative.subjectReference
                else {
                    continue
                }

                do {
                    let state = try await client.fetchSubjectResolutionState(
                        token: token,
                        reference: subjectReference,
                        login: userLogin
                    )
                    if let transition = AttentionRemovalNotificationPolicy.notification(
                        for: removedGroup,
                        state: state
                    ) {
                        notifier.notify(transition: transition)
                        deliveredTransitionNotifications += 1
                    }
                } catch {
                    continue
                }
            }
        }

        knownItemIDs = currentIDs
    }

    private func applyingLocalReadState(to item: AttentionItem) -> AttentionItem {
        var updated = item
        let locallyUnread = isLocallyUnread(item)
        updated.isUnread = item.isUnread && locallyUnread
        return updated
    }

    private func isLocallyUnread(_ item: AttentionItem) -> Bool {
        guard let readAt = readStateByItemID[item.id] else {
            return true
        }
        return readAt < item.timestamp
    }

    private func updateReadState(for item: AttentionItem, isUnread: Bool) {
        if isUnread {
            readStateByItemID[item.id] = nil
        } else {
            readStateByItemID[item.id] = Date()
        }

        persistReadState()

        if let index = attentionItems.firstIndex(where: { $0.id == item.id }) {
            attentionItems[index].isUnread = isUnread
        }
    }

    private func persistReadState() {
        let raw = readStateByItemID.mapValues(\.timeIntervalSince1970)
        UserDefaults.standard.set(raw, forKey: readStateStoreKey)
    }

    private func persistIgnoredItems() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = ignoredItems.sorted { $0.ignoredAt > $1.ignoredAt }

        if let data = try? encoder.encode(payload) {
            UserDefaults.standard.set(data, forKey: ignoredSubjectStoreKey)
            UserDefaults.standard.removeObject(forKey: legacyIgnoredSubjectStoreKey)
        }
    }

    private func persistNotificationScanState() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if let data = try? encoder.encode(notificationScanState.normalized) {
            UserDefaults.standard.set(data, forKey: notificationScanStateStoreKey)
        }
    }

    private func persistTeamMembershipCache() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if let data = try? encoder.encode(teamMembershipCache.normalized) {
            UserDefaults.standard.set(data, forKey: teamMembershipStoreKey)
        }
    }

    private func syncIgnoredItems() {
        ignoredItems = ignoredItemsByKey.values.sorted { lhs, rhs in
            if lhs.ignoredAt == rhs.ignoredAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.ignoredAt > rhs.ignoredAt
        }
    }

    private func presentIgnoreUndo(for ignoredItem: IgnoredAttentionSubject) {
        ignoreUndoDismissTask?.cancel()

        let expiry = Date().addingTimeInterval(8)
        ignoreUndoState = IgnoreUndoState(subject: ignoredItem, expiresAt: expiry)

        ignoreUndoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self?.ignoreUndoState?.subject.ignoreKey == ignoredItem.ignoreKey else {
                    return
                }

                self?.clearIgnoreUndoState()
            }
        }
    }

    private func clearIgnoreUndoState() {
        ignoreUndoDismissTask?.cancel()
        ignoreUndoDismissTask = nil
        ignoreUndoState = nil
    }

    private static func loadReadState(
        from defaults: UserDefaults,
        key: String
    ) -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: Double] else {
            return [:]
        }

        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func loadIgnoredItems(
        from defaults: UserDefaults,
        key: String
    ) -> [String: IgnoredAttentionSubject]? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let items = try? decoder.decode([IgnoredAttentionSubject].self, from: data) else {
            return nil
        }

        return Dictionary(uniqueKeysWithValues: items.map { ($0.ignoreKey, $0) })
    }

    private static func loadLegacyIgnoredItems(
        from defaults: UserDefaults,
        key: String
    ) -> [String: IgnoredAttentionSubject] {
        let keys = defaults.stringArray(forKey: key) ?? []
        let items = keys.map { IgnoredAttentionSubject.placeholder(for: $0) }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.ignoreKey, $0) })
    }

    private func preferredIgnoredSummary(for item: AttentionItem) -> IgnoredAttentionSubject {
        let representative = attentionItems
            .filter { $0.ignoreKey == item.ignoreKey }
            .max { lhs, rhs in
                let lhsScore = ignoreSummaryPriority(for: lhs)
                let rhsScore = ignoreSummaryPriority(for: rhs)

                if lhsScore == rhsScore {
                    return lhs.timestamp < rhs.timestamp
                }

                return lhsScore < rhsScore
            } ?? item

        return IgnoredAttentionSubject(
            ignoreKey: representative.ignoreKey,
            title: representative.title,
            subtitle: representative.subtitle,
            url: representative.url,
            ignoredAt: Date()
        )
    }

    private func ignoreSummaryPriority(for item: AttentionItem) -> Int {
        switch item.type {
        case .assignedPullRequest,
                .authoredPullRequest,
                .reviewedPullRequest,
                .commentedPullRequest,
                .readyToMerge,
                .assignedIssue,
                .authoredIssue,
                .commentedIssue:
            return 4
        case .reviewRequested,
            .teamReviewRequested,
            .reviewApproved,
            .reviewChangesRequested,
            .reviewComment,
            .newCommitsAfterComment,
            .newCommitsAfterReview,
            .comment,
            .mention,
            .teamMention,
            .pullRequestStateChanged:
            return 3
        case .workflowFailed, .workflowApprovalRequired, .ciActivity:
            return 2
        }
    }

    private static func normalizedPollInterval(_ seconds: Int) -> Int {
        let available = [30, 60, 120, 300, 600, 900]
        if available.contains(seconds) {
            return seconds
        }

        return 60
    }

    private static func loadPollInterval(from defaults: UserDefaults, key: String) -> Int {
        let stored = defaults.integer(forKey: key)
        if stored == 0 {
            return 60
        }

        return normalizedPollInterval(stored)
    }

    private static func loadAutoMarkReadSetting(
        from defaults: UserDefaults,
        key: String
    ) -> AutoMarkReadSetting {
        AutoMarkReadSetting.normalized(rawValue: defaults.object(forKey: key) as? Int ?? 3)
    }

    private static func loadNotificationScanState(
        from defaults: UserDefaults,
        key: String
    ) -> NotificationScanState {
        guard
            let data = defaults.data(forKey: key),
            let state = try? JSONDecoder().decode(NotificationScanState.self, from: data)
        else {
            return .default
        }

        return state.normalized
    }

    private static func loadTeamMembershipCache(
        from defaults: UserDefaults,
        key: String
    ) -> TeamMembershipCache {
        guard
            let data = defaults.data(forKey: key),
            let cache = try? JSONDecoder().decode(TeamMembershipCache.self, from: data)
        else {
            return .default
        }

        return cache.normalized
    }

    private func effectiveAutomaticPollInterval(relativeTo referenceDate: Date) -> Int {
        rateLimit?.minimumAutomaticRefreshInterval(
            userConfiguredSeconds: pollIntervalSeconds,
            now: referenceDate
        ) ?? pollIntervalSeconds
    }

    private func shouldDelayAutomaticRefresh(relativeTo referenceDate: Date) -> Bool {
        guard let rateLimit, rateLimit.isExhausted, let resetAt = rateLimit.resetAt else {
            return false
        }

        return resetAt.timeIntervalSince(referenceDate) > 1
    }

    private func formatInterval(_ seconds: Int) -> String {
        if seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        if seconds % 60 == 0 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }

    private func applyLaunchFixture(_ fixture: LaunchFixture) {
        token = "ui-test-token"
        tokenInput = ""
        userLogin = fixture.login
        attentionItems = fixture.attentionItems
        lastUpdated = fixture.lastUpdated
        lastError = nil
        isResolvingInitialContent = false
        gitHubCLIAvailable = false
        usingGitHubCLIToken = false
        isValidatingToken = false
        rateLimit = nil
        knownItemIDs = Set(fixture.attentionItems.map(\.id))
        ignoredItemsByKey = [:]
        ignoredItems = []
        readStateByItemID = [:]
        autoMarkReadSetting = fixture.autoMarkReadSetting
        notificationScanState = .default
        teamMembershipCache = .default
        pullRequestFocusCache = [:]
        suppressedTransitionNotificationKeys = []
    }
}

private struct LaunchFixture {
    let login: String
    let attentionItems: [AttentionItem]
    let autoMarkReadSetting: AutoMarkReadSetting
    let lastUpdated: Date

    static func load(from environment: [String: String]) -> LaunchFixture? {
        switch environment["OCTOWATCH_UI_TEST_FIXTURE"] {
        case "auto-mark-read":
            return autoMarkReadFixture
        default:
            return nil
        }
    }

    private static var autoMarkReadFixture: LaunchFixture {
        let now = Date()
        let repository = "example/octowatch"

        let primaryItem = AttentionItem(
            id: "fixture-primary",
            ignoreKey: "https://github.com/\(repository)/pull/1",
            type: .reviewRequested,
            title: "Primary fixture item",
            subtitle: "\(repository) · Review requested",
            timestamp: now.addingTimeInterval(-300),
            url: URL(string: "https://github.com/\(repository)/pull/1")!,
            actor: AttentionActor(
                login: "octowatch-fixture",
                avatarURL: URL(string: "https://avatars.githubusercontent.com/u/9919?v=4")
            ),
            isUnread: false
        )

        let secondaryItem = AttentionItem(
            id: "fixture-secondary",
            ignoreKey: "https://github.com/\(repository)/pull/2",
            type: .comment,
            title: "Secondary fixture item",
            subtitle: "\(repository) · New comment",
            timestamp: now.addingTimeInterval(-180),
            url: URL(string: "https://github.com/\(repository)/pull/2")!,
            actor: AttentionActor(
                login: "octowatch-helper",
                avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1342004?v=4")
            ),
            isUnread: true
        )

        return LaunchFixture(
            login: "octowatch-ui-test",
            attentionItems: [primaryItem, secondaryItem],
            autoMarkReadSetting: .oneSecond,
            lastUpdated: now
        )
    }
}

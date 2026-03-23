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
    @Published private(set) var rateLimitBuckets: [GitHubRateLimit] = []

    @Published var tokenInput = ""
    @Published private(set) var isResolvingInitialContent = true
    @Published private(set) var gitHubCLIAvailable = false
    @Published private(set) var usingGitHubCLIToken = false
    @Published private(set) var isValidatingToken = false
    @Published private(set) var ignoredItems: [IgnoredAttentionSubject] = []
    @Published private(set) var ignoreUndoState: IgnoreUndoState?
    @Published private(set) var pollIntervalSeconds = 60
    @Published private(set) var autoMarkReadSetting: AutoMarkReadSetting = .threeSeconds
    @Published private(set) var notifyOnSelfTriggeredUpdates = false
    @Published private(set) var pullRequestWatchRevision = 0
    @Published private(set) var showsDebugRateLimitDetails = false
    @Published private(set) var needsActionConfiguration: NeedsActionConfiguration = .default
    @Published private(set) var needsActionItems: [AttentionItem] = []

    private let readStateStoreKey = "attention-subject-read-state-v2"
    private let ignoredSubjectStoreKey = "ignored-attention-subjects-v2"
    private let legacyIgnoredSubjectStoreKey = "ignored-attention-subjects-v1"
    private let pollIntervalStoreKey = "poll-interval-seconds-v1"
    private let autoMarkReadStoreKey = "auto-mark-read-setting-v1"
    private let notifyOnSelfTriggeredUpdatesStoreKey = "notify-on-self-triggered-updates-v1"
    private let debugRateLimitDetailsStoreKey = "debug-rate-limit-details-v1"
    private let needsActionConfigurationStoreKey = "needs-action-configuration-v2"
    private let legacyNeedsActionConfigurationStoreKey = "needs-action-configuration-v1"
    private let notificationScanStateStoreKey = "notification-scan-state-v1"
    private let teamMembershipStoreKey = "team-membership-cache-v1"
    private let postMergeWatchStoreKey = "post-merge-watches-v1"
    private let mergeMethodPreferenceStoreKey = "merge-method-preferences-v1"
    private let attentionUpdateHistoryStoreKey = "attention-update-history-v1"
    private let client = GitHubClient()
    private let notifier = UserNotifier()
    private let pullRequestFocusCacheTTL: TimeInterval = 300
    private let focusedPullRequestWatchIntervalSeconds = 5
    private let queuedPostMergeWatchIntervalSeconds = 20

    private struct PullRequestFocusCacheEntry {
        let focus: PullRequestFocus
        let subjectRefresh: AttentionSubjectRefresh
        let sourceTimestamp: Date
        let loadedAt: Date
    }

    private var token: String?
    private var userLogin: String?
    private var pollingTask: Task<Void, Never>?
    private var watchedPullRequestTask: Task<Void, Never>?
    private var queuedPostMergeWatchTask: Task<Void, Never>?
    private var latestSnapshotAttentionItems: [AttentionItem] = []
    private var knownLatestUpdateKeyBySubjectKey = [String: String]()
    private var notificationScanState = NotificationScanState.default
    private var teamMembershipCache = TeamMembershipCache.default
    private var postMergeWatchesByKey = [String: PostMergeWatch]()
    private var pullRequestFocusCache = [String: PullRequestFocusCacheEntry]()
    private var watchedPullRequestKey: String?
    private var watchedPullRequestState: PullRequestLiveWatchState?
    private var ignoredItemsByKey = [String: IgnoredAttentionSubject]()
    private var mergeMethodPreferenceByRepository = [String: PullRequestMergeMethod]()
    private var ignoreUndoDismissTask: Task<Void, Never>?
    private var readStateBySubjectKey: [String: Date] = [:]
    private var updateHistoryBySubjectKey = [String: [AttentionUpdate]]()
    private var suppressedTransitionNotificationKeys = Set<String>()
    private var pendingForcedRefresh = false
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
        notifyOnSelfTriggeredUpdates = Self.loadBooleanSetting(
            from: UserDefaults.standard,
            key: notifyOnSelfTriggeredUpdatesStoreKey
        )
        showsDebugRateLimitDetails = Self.loadBooleanSetting(
            from: UserDefaults.standard,
            key: debugRateLimitDetailsStoreKey
        )
        needsActionConfiguration = Self.loadNeedsActionConfiguration(
            from: UserDefaults.standard,
            key: needsActionConfigurationStoreKey,
            legacyKey: legacyNeedsActionConfigurationStoreKey
        )
        notificationScanState = Self.loadNotificationScanState(
            from: UserDefaults.standard,
            key: notificationScanStateStoreKey
        )
        teamMembershipCache = Self.loadTeamMembershipCache(
            from: UserDefaults.standard,
            key: teamMembershipStoreKey
        )
        postMergeWatchesByKey = Self.loadPostMergeWatches(
            from: UserDefaults.standard,
            key: postMergeWatchStoreKey
        )
        mergeMethodPreferenceByRepository = Self.loadMergeMethodPreferences(
            from: UserDefaults.standard,
            key: mergeMethodPreferenceStoreKey
        )
        readStateBySubjectKey = Self.loadReadState(
            from: UserDefaults.standard,
            key: readStateStoreKey
        )
        updateHistoryBySubjectKey = AttentionUpdateHistoryStore.load(
            from: UserDefaults.standard,
            key: attentionUpdateHistoryStoreKey
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
        watchedPullRequestTask?.cancel()
        queuedPostMergeWatchTask?.cancel()
        ignoreUndoDismissTask?.cancel()
    }

    var hasToken: Bool {
        !(token ?? "").isEmpty
    }

    var viewerLogin: String? {
        userLogin
    }

    var actionableCount: Int {
        actionableAttentionItems.count
    }

    var unreadCount: Int {
        actionableAttentionItems.filter { $0.isUnread }.count
    }

    var combinedAttentionItems: [AttentionItem] {
        attentionItems
    }

    var actionableAttentionItems: [AttentionItem] {
        AttentionItemVisibilityPolicy.excludingHistoricalLogEntries(combinedAttentionItems)
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
        rateLimitBuckets.contains { $0.isLow || $0.isExhausted }
    }

    func setShowsDebugRateLimitDetails(_ value: Bool) {
        guard showsDebugRateLimitDetails != value else {
            return
        }

        showsDebugRateLimitDetails = value
        UserDefaults.standard.set(value, forKey: debugRateLimitDetailsStoreKey)
    }

    func setNotifyOnSelfTriggeredUpdates(_ value: Bool) {
        guard notifyOnSelfTriggeredUpdates != value else {
            return
        }

        notifyOnSelfTriggeredUpdates = value
        UserDefaults.standard.set(value, forKey: notifyOnSelfTriggeredUpdatesStoreKey)
    }

    func setNeedsActionRuleEnabled(_ ruleID: UUID, isEnabled: Bool) {
        guard let existingRule = needsActionConfiguration.rules.first(where: { $0.id == ruleID }) else {
            return
        }

        var updatedRule = existingRule
        updatedRule.isEnabled = isEnabled
        let updatedConfiguration = needsActionConfiguration.replacing(updatedRule)
        guard updatedConfiguration != needsActionConfiguration else {
            return
        }

        needsActionConfiguration = updatedConfiguration
        refreshNeedsActionItems()
        persistNeedsActionConfiguration()
    }

    @discardableResult
    func saveNeedsActionRule(_ rule: NeedsActionRuleDefinition) -> NeedsActionRuleDefinition {
        let normalizedRule = rule.normalized
        let updatedConfiguration = needsActionConfiguration.replacing(normalizedRule)
        needsActionConfiguration = updatedConfiguration
        refreshNeedsActionItems()
        persistNeedsActionConfiguration()
        return normalizedRule
    }

    func duplicateNeedsActionRule(_ ruleID: UUID) {
        guard let existingRule = needsActionConfiguration.rules.first(where: { $0.id == ruleID }) else {
            return
        }

        var duplicatedRule = existingRule
        duplicatedRule.id = UUID()
        _ = saveNeedsActionRule(duplicatedRule)
    }

    func deleteNeedsActionRule(_ ruleID: UUID) {
        let updatedConfiguration = needsActionConfiguration.removingRule(id: ruleID)
        guard updatedConfiguration != needsActionConfiguration else {
            return
        }

        needsActionConfiguration = updatedConfiguration
        refreshNeedsActionItems()
        persistNeedsActionConfiguration()
    }

    func resetNeedsActionRules() {
        guard needsActionConfiguration != .default else {
            return
        }

        needsActionConfiguration = .default
        refreshNeedsActionItems()
        persistNeedsActionConfiguration()
    }

    func rateLimitBucketSummary(
        for rateLimit: GitHubRateLimit,
        relativeTo referenceDate: Date
    ) -> String {
        var segments = ["\(rateLimit.resourceDisplayName) \(rateLimit.remaining)/\(rateLimit.limit)"]

        if let resetAt = rateLimit.resetAt {
            let resetDelta = resetAt.timeIntervalSince(referenceDate)
            if abs(resetDelta) < 1 {
                segments.append("resets now")
            } else if resetDelta > 1 {
                segments.append(
                    "resets \(relativeDateFormatter.localizedString(for: resetAt, relativeTo: referenceDate))"
                )
            }
        }

        if let pollIntervalHint = rateLimit.pollIntervalHintSeconds,
            pollIntervalHint > pollIntervalSeconds {
            segments.append("hint \(pollIntervalHint)s")
        }

        return segments.joined(separator: " · ")
    }

    func rateLimitDebugHeader(relativeTo referenceDate: Date) -> String? {
        guard let rateLimit else {
            return nil
        }

        var segments = ["Most restrictive: \(rateLimit.resourceDisplayName)"]

        let effectiveInterval = rateLimit.minimumAutomaticRefreshInterval(
            userConfiguredSeconds: pollIntervalSeconds,
            now: referenceDate
        )
        if effectiveInterval != pollIntervalSeconds {
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
        let existingSubjectKeys = Array(attentionItems.map(\.subjectKey))

        token = nil
        tokenInput = ""
        usingGitHubCLIToken = false
        latestSnapshotAttentionItems = []
        attentionItems = []
        needsActionItems = []
        userLogin = nil
        lastUpdated = nil
        lastError = nil
        clearRateLimitState()
        knownLatestUpdateKeyBySubjectKey.removeAll()
        notificationScanState = .default
        teamMembershipCache = .default
        pullRequestFocusCache = [:]
        suppressedTransitionNotificationKeys = []
        isResolvingInitialContent = false
        clearIgnoreUndoState()
        notifier.removeSubjectNotifications(subjectKeys: existingSubjectKeys)
        UserDefaults.standard.removeObject(forKey: notificationScanStateStoreKey)
        UserDefaults.standard.removeObject(forKey: teamMembershipStoreKey)
        UserDefaults.standard.removeObject(forKey: postMergeWatchStoreKey)
        UserDefaults.standard.removeObject(forKey: attentionUpdateHistoryStoreKey)
        postMergeWatchesByKey.removeAll()
        updateHistoryBySubjectKey.removeAll()

        pollingTask?.cancel()
        pollingTask = nil
        clearWatchedPullRequest()
        clearQueuedPostMergeWatchLoop()
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
        Task {
            await forceRefresh()
        }
    }

    func forceRefresh(item: AttentionItem? = nil) async {
        if let item, item.pullRequestReference != nil {
            pullRequestFocusCache[item.ignoreKey] = nil
            pullRequestWatchRevision &+= 1
        }

        await refresh(force: true)
    }

    func setWatchedPullRequest(_ item: AttentionItem?) {
        guard hasToken, let item, let reference = item.pullRequestReference else {
            clearWatchedPullRequest()
            return
        }

        let watchKey = item.ignoreKey
        if let cached = pullRequestFocusCache[watchKey], cached.focus.resolution != .open {
            clearWatchedPullRequest()
            return
        }

        if watchedPullRequestKey == watchKey, watchedPullRequestTask != nil {
            return
        }

        watchedPullRequestTask?.cancel()
        watchedPullRequestKey = watchKey
        watchedPullRequestState = nil
        watchedPullRequestTask = Task { [weak self] in
            await self?.runWatchedPullRequestLoop(reference: reference, cacheKey: watchKey)
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
            applyPullRequestFocusSubjectRefresh(cached.subjectRefresh)
            return cached.focus
        }

        let result = try await client.fetchPullRequestFocus(
            token: token,
            login: userLogin,
            reference: reference,
            sourceType: item.focusType ?? item.type,
            sourceActor: item.focusActor ?? item.actor
        )
        let preferredMergeMethod = preferredMergeMethod(
            for: reference,
            allowedMethods: result.focus.reviewMergeAction?.allowedMergeMethods ?? [],
            fallback: result.focus.reviewMergeAction?.preferredMergeMethod
        )
        let previousFocus = pullRequestFocusCache[cacheKey]?.focus
        let focus = result.focus
            .applyingPreferredMergeMethod(preferredMergeMethod)
            .restoringPostMergeWorkflowPreview(from: previousFocus)

        mergeRateLimitState(with: result.rateLimits)
        applyPullRequestFocusSubjectRefresh(result.subjectRefresh)

        pullRequestFocusCache[cacheKey] = PullRequestFocusCacheEntry(
            focus: focus,
            subjectRefresh: result.subjectRefresh,
            sourceTimestamp: item.timestamp,
            loadedAt: Date()
        )

        return focus
    }

    func rememberPreferredMergeMethod(
        _ mergeMethod: PullRequestMergeMethod,
        for reference: PullRequestReference
    ) {
        let repositoryKey = mergeMethodPreferenceKey(for: reference)
        guard mergeMethodPreferenceByRepository[repositoryKey] != mergeMethod else {
            return
        }

        mergeMethodPreferenceByRepository[repositoryKey] = mergeMethod
        pullRequestFocusCache = pullRequestFocusCache.mapValues { entry in
            guard mergeMethodPreferenceKey(for: entry.focus.reference) == repositoryKey else {
                return entry
            }

            return PullRequestFocusCacheEntry(
                focus: entry.focus.applyingPreferredMergeMethod(mergeMethod),
                subjectRefresh: entry.subjectRefresh,
                sourceTimestamp: entry.sourceTimestamp,
                loadedAt: entry.loadedAt
            )
        }
        persistMergeMethodPreferences()
    }

    func approveAndMergePullRequest(
        for item: AttentionItem,
        requiresApproval: Bool,
        mergeMethod: PullRequestMergeMethod?
    ) async throws -> PullRequestMutationOutcome {
        guard let reference = item.pullRequestReference, let token else {
            throw GitHubClientError.invalidResponse
        }

        let mutationResult = try await client.approveAndMergePullRequest(
            token: token,
            reference: reference,
            approveFirst: requiresApproval,
            selectedMergeMethod: mergeMethod
        )

        mergeRateLimitState(with: mutationResult.rateLimits)

        if let mergedWithMethod = mutationResult.mergeMethod {
            rememberPreferredMergeMethod(mergedWithMethod, for: reference)
        }

        markItemAsRead(item)
        suppressedTransitionNotificationKeys.insert(item.ignoreKey)
        registerPostMergeWatch(for: item, outcome: mutationResult.outcome)
        pullRequestFocusCache[item.ignoreKey] = nil
        return mutationResult.outcome
    }

    func fetchPendingDeploymentReview(
        for target: WorkflowApprovalTarget
    ) async throws -> WorkflowPendingDeploymentReview {
        guard let token else {
            throw GitHubClientError.invalidResponse
        }

        let result = try await client.fetchPendingDeploymentReview(
            token: token,
            target: target
        )
        mergeRateLimitState(with: result.rateLimits)
        return result.review
    }

    func reviewPendingDeployments(
        for target: WorkflowApprovalTarget,
        environmentIDs: [Int],
        decision: WorkflowPendingDeploymentDecision,
        comment: String,
        sourceItem: AttentionItem?
    ) async throws {
        guard let token else {
            throw GitHubClientError.invalidResponse
        }

        let result = try await client.reviewPendingDeployments(
            token: token,
            target: target,
            environmentIDs: environmentIDs,
            decision: decision,
            comment: comment
        )
        mergeRateLimitState(with: result.rateLimits)

        if let sourceItem {
            markItemAsRead(sourceItem)

            if sourceItem.pullRequestReference != nil {
                pullRequestFocusCache[sourceItem.ignoreKey] = nil
                pullRequestWatchRevision &+= 1
            }
        }

        await refresh(force: true)
    }

    func markItemAsRead(_ item: AttentionItem) {
        updateReadState(for: [item], isUnread: false)
    }

    func markItemsAsRead(_ items: [AttentionItem]) {
        updateReadState(for: items, isUnread: false)
    }

    func markItemsAsUnread(_ items: [AttentionItem]) {
        updateReadState(for: items, isUnread: true)
    }

    func toggleReadState(for item: AttentionItem) {
        updateReadState(for: [item], isUnread: !item.isUnread)
    }

    func ignore(_ item: AttentionItem) {
        ignore([item])
    }

    func ignore(_ items: [AttentionItem]) {
        var ignoredSummaries: [IgnoredAttentionSubject] = []
        var ignoredKeys = Set<String>()

        for item in items {
            guard ignoredKeys.insert(item.ignoreKey).inserted else {
                continue
            }

            let summary = preferredIgnoredSummary(for: item)
            ignoredItemsByKey[item.ignoreKey] = summary
            ignoredSummaries.append(summary)
        }

        guard !ignoredSummaries.isEmpty else {
            return
        }

        syncIgnoredItems()
        persistIgnoredItems()
        presentIgnoreUndo(for: ignoredSummaries)
        notifier.removeSubjectNotifications(subjectKeys: Array(ignoredKeys))
        reconcileAttentionItemsFromSnapshot()
    }

    func unignore(_ ignoredItem: IgnoredAttentionSubject) {
        unignore([ignoredItem])
    }

    func undoRecentIgnore() {
        guard let ignoreUndoState else {
            return
        }

        unignore(ignoreUndoState.subjects)
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

    private func clearWatchedPullRequest() {
        watchedPullRequestTask?.cancel()
        watchedPullRequestTask = nil
        watchedPullRequestKey = nil
        watchedPullRequestState = nil
    }

    private func clearQueuedPostMergeWatchLoop() {
        queuedPostMergeWatchTask?.cancel()
        queuedPostMergeWatchTask = nil
    }

    private func syncQueuedPostMergeWatchLoop() {
        guard hasToken, hasQueuedPostMergeWatches else {
            clearQueuedPostMergeWatchLoop()
            return
        }

        guard queuedPostMergeWatchTask == nil else {
            return
        }

        queuedPostMergeWatchTask = Task { [weak self] in
            await self?.runQueuedPostMergeWatchLoop()
        }
    }

    private func runWatchedPullRequestLoop(
        reference: PullRequestReference,
        cacheKey: String
    ) async {
        defer {
            if watchedPullRequestKey == cacheKey {
                watchedPullRequestTask = nil
            }
        }

        while !Task.isCancelled {
            let shouldContinue = await pollWatchedPullRequest(
                reference: reference,
                cacheKey: cacheKey
            )

            guard shouldContinue, !Task.isCancelled else {
                return
            }

            let interval = effectiveFocusedPullRequestWatchInterval(relativeTo: .now)
            try? await Task.sleep(for: .seconds(Double(interval)))
        }
    }

    private func runQueuedPostMergeWatchLoop() async {
        defer {
            queuedPostMergeWatchTask = nil
        }

        while !Task.isCancelled {
            let shouldContinue = await pollQueuedPostMergeWatches()

            guard shouldContinue, !Task.isCancelled else {
                return
            }

            let interval = effectiveQueuedPostMergeWatchInterval(relativeTo: .now)
            try? await Task.sleep(for: .seconds(Double(interval)))
        }
    }

    private func pollWatchedPullRequest(
        reference: PullRequestReference,
        cacheKey: String
    ) async -> Bool {
        guard watchedPullRequestKey == cacheKey, let token else {
            return false
        }

        do {
            let result = try await client.fetchPullRequestLiveWatchUpdate(
                token: token,
                reference: reference,
                previous: watchedPullRequestState
            )

            mergeRateLimitState(with: result.rateLimits)

            watchedPullRequestState = result.update.state

            if result.update.shouldReloadFocus {
                pullRequestFocusCache[cacheKey] = nil
                pullRequestWatchRevision &+= 1
            }

            if result.update.shouldRefreshSnapshot {
                await refresh(force: true)
            }

            return result.update.shouldContinueWatching
        } catch {
            return true
        }
    }

    private func pollQueuedPostMergeWatches() async -> Bool {
        guard hasQueuedPostMergeWatches, let token else {
            return false
        }

        let shouldRefreshSnapshot = await processPostMergeWatches(
            token: token,
            onlyQueued: true
        )
        if shouldRefreshSnapshot {
            requestForcedRefresh()
        }

        return hasQueuedPostMergeWatches
    }

    private var hasQueuedPostMergeWatches: Bool {
        postMergeWatchesByKey.values.contains { watch in
            watch.queuedAt != nil && watch.mergedAt == nil
        }
    }

    private func requestForcedRefresh() {
        if isRefreshing {
            pendingForcedRefresh = true
            return
        }

        Task { [weak self] in
            await self?.refresh(force: true)
        }
    }

    private func refresh(force: Bool) async {
        guard hasToken else {
            return
        }

        guard !isRefreshing else {
            if force {
                pendingForcedRefresh = true
            }
            return
        }

        guard let token else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false

            if pendingForcedRefresh {
                pendingForcedRefresh = false
                Task { [weak self] in
                    await self?.refresh(force: true)
                }
            }
        }

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
            replaceRateLimitState(with: snapshot.rateLimits)
            notificationScanState = snapshot.notificationScanState.normalized
            teamMembershipCache = snapshot.teamMembershipCache.normalized
            persistNotificationScanState()
            persistTeamMembershipCache()
            latestSnapshotAttentionItems = snapshot.attentionItems
            reconcileAttentionItemsFromSnapshot()
            lastUpdated = Date()
            lastError = nil

            let shouldRefreshSnapshot = await processPostMergeWatches(token: token)
            if shouldRefreshSnapshot {
                pendingForcedRefresh = true
            }
            await notifyIfNeeded(previousItems: previousItems, token: token)
        } catch {
            if let clientError = error as? GitHubClientError,
                case let .rateLimited(rateLimit) = clientError {
                mergeRateLimitState(with: rateLimit)
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
            knownLatestUpdateKeyBySubjectKey.removeAll()
            lastError = nil
            clearRateLimitState()
            pullRequestFocusCache = [:]
            suppressedTransitionNotificationKeys = []
            isResolvingInitialContent = false

            if previousLogin?.caseInsensitiveCompare(validatedLogin) != .orderedSame {
                teamMembershipCache = .default
                postMergeWatchesByKey.removeAll()
                updateHistoryBySubjectKey.removeAll()
                UserDefaults.standard.removeObject(forKey: teamMembershipStoreKey)
                UserDefaults.standard.removeObject(forKey: postMergeWatchStoreKey)
                UserDefaults.standard.removeObject(forKey: attentionUpdateHistoryStoreKey)
                clearWatchedPullRequest()
                clearQueuedPostMergeWatchLoop()
            }

            startPollingIfNeeded()
            syncQueuedPostMergeWatchLoop()
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
        let currentItemsBySubjectKey = Dictionary(
            uniqueKeysWithValues: attentionItems.map { ($0.subjectKey, $0) }
        )
        let suppressedWorkflowItemIDs = Set(
            postMergeWatchesByKey.values.flatMap(\.suppressedWorkflowItemIDs)
        )
        var registeredNewPostMergeWatch = false
        let newItems = attentionItems
            .filter { knownLatestUpdateKeyBySubjectKey[$0.subjectKey] != $0.updateKey }
            .sorted { $0.timestamp < $1.timestamp }

        if !knownLatestUpdateKeyBySubjectKey.isEmpty {
            var deliveredItemNotifications = 0
            for item in newItems {
                guard deliveredItemNotifications < 5 else {
                    break
                }

                if suppressedWorkflowItemIDs.contains(item.latestSourceID) {
                    continue
                }

                if item.isHistoricalLogEntry {
                    continue
                }

                if !AttentionUpdateNotificationPolicy.shouldDeliver(
                    item: item,
                    includeSelfTriggeredUpdates: notifyOnSelfTriggeredUpdates
                ) {
                    notifier.removeSubjectNotifications(subjectKeys: [item.subjectKey])
                    continue
                }

                notifier.notify(item: item)
                deliveredItemNotifications += 1
            }

            let removedItems = previousItems
                .filter { currentItemsBySubjectKey[$0.subjectKey] == nil }
                .sorted { $0.timestamp > $1.timestamp }

            notifier.removeSubjectNotifications(subjectKeys: removedItems.map(\.subjectKey))

            var deliveredTransitionNotifications = 0
            for removedItem in removedItems {
                guard deliveredTransitionNotifications < 3 else {
                    break
                }

                if suppressedTransitionNotificationKeys.remove(removedItem.subjectKey) != nil {
                    continue
                }

                guard
                    let subjectReference = removedItem.subjectReference
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
                        for: [removedItem],
                        state: state
                    ) {
                        notifier.notify(transition: transition)
                        deliveredTransitionNotifications += 1
                    }

                    if registerResolvedPostMergeWatchIfNeeded(
                        for: [removedItem],
                        state: state
                    ) {
                        registeredNewPostMergeWatch = true
                    }
                } catch {
                    continue
                }
            }
        }

        knownLatestUpdateKeyBySubjectKey = Dictionary(
            uniqueKeysWithValues: attentionItems.map { ($0.subjectKey, $0.updateKey) }
        )

        if registeredNewPostMergeWatch {
            await processPostMergeWatches(token: token)
        }
    }

    private func registerPostMergeWatch(
        for item: AttentionItem,
        outcome: PullRequestMutationOutcome
    ) {
        guard let watch = PostMergeWatch.register(item: item, outcome: outcome) else {
            return
        }

        postMergeWatchesByKey[watch.id] = watch
        persistPostMergeWatches()
        syncQueuedPostMergeWatchLoop()
    }

    private func registerResolvedPostMergeWatchIfNeeded(
        for removedItems: [AttentionItem],
        state: GitHubSubjectResolutionState
    ) -> Bool {
        guard let watch = AttentionRemovalPostMergeWatchPolicy.watch(
            for: removedItems,
            state: state
        ) else {
            return false
        }

        if let existing = postMergeWatchesByKey[watch.id] {
            let updatedWatch = existing.updating(
                mergedAt: state.mergedAt ?? existing.mergedAt,
                mergeCommitSHA: state.mergeCommitSHA ?? existing.mergeCommitSHA
            )

            guard updatedWatch != existing else {
                return false
            }

            postMergeWatchesByKey[watch.id] = updatedWatch
            persistPostMergeWatches()
            syncQueuedPostMergeWatchLoop()
            return true
        }

        postMergeWatchesByKey[watch.id] = watch
        persistPostMergeWatches()
        syncQueuedPostMergeWatchLoop()
        return true
    }

    @discardableResult
    private func processPostMergeWatches(
        token: String,
        onlyQueued: Bool = false
    ) async -> Bool {
        guard !postMergeWatchesByKey.isEmpty else {
            syncQueuedPostMergeWatchLoop()
            return false
        }

        var updatedWatches = postMergeWatchesByKey
        let watchKeys = updatedWatches.keys.sorted().filter { watchKey in
            guard
                onlyQueued,
                let watch = updatedWatches[watchKey]
            else {
                return true
            }

            return watch.queuedAt != nil && watch.mergedAt == nil
        }
        guard !watchKeys.isEmpty else {
            syncQueuedPostMergeWatchLoop()
            return false
        }
        var shouldRefreshSnapshot = false

        for watchKey in watchKeys {
            guard let watch = updatedWatches[watchKey] else {
                continue
            }

            do {
                let result = try await client.fetchPostMergeWatchObservation(
                    token: token,
                    watch: watch
                )

                mergeRateLimitState(with: result.rateLimits)

                let update = PostMergeWatchPolicy.apply(
                    watch: watch,
                    observation: result.observation
                )

                if PostMergeWatchRefreshPolicy.shouldRefreshSnapshot(
                    watch: watch,
                    observation: result.observation
                ) {
                    shouldRefreshSnapshot = true
                }

                if result.observation.resolution != .open || !result.observation.workflowRuns.isEmpty {
                    pullRequestFocusCache[watch.reference.pullRequestURL.absoluteString] = nil
                }

                if let updatedWatch = update.updatedWatch {
                    updatedWatches[watchKey] = updatedWatch
                } else {
                    updatedWatches[watchKey] = nil
                }

                for notification in update.notifications {
                    notifier.notify(transition: notification)
                }
            } catch {
                continue
            }
        }

        postMergeWatchesByKey = updatedWatches
        persistPostMergeWatches()
        syncQueuedPostMergeWatchLoop()
        return shouldRefreshSnapshot
    }

    private func applyingLocalReadState(to item: AttentionItem) -> AttentionItem {
        var updated = item
        let locallyUnread = isLocallyUnread(item)
        updated.isUnread = item.isUnread && locallyUnread
        return updated
    }

    private func isLocallyUnread(_ item: AttentionItem) -> Bool {
        guard let readAt = readStateBySubjectKey[item.subjectKey] else {
            return true
        }
        return readAt < item.timestamp
    }

    private func updateReadState(for items: [AttentionItem], isUnread: Bool) {
        let subjectKeys = Set(items.map(\.subjectKey))
        guard !subjectKeys.isEmpty else {
            return
        }

        let timestamp = Date()
        for subjectKey in subjectKeys {
            if isUnread {
                readStateBySubjectKey[subjectKey] = nil
            } else {
                readStateBySubjectKey[subjectKey] = timestamp
            }
        }

        persistReadState()
        if !isUnread {
            notifier.removeSubjectNotifications(subjectKeys: Array(subjectKeys))
        }
        reconcileAttentionItemsFromSnapshot()
    }

    private func persistReadState() {
        let raw = readStateBySubjectKey.mapValues(\.timeIntervalSince1970)
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

    private func persistNeedsActionConfiguration() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if let data = try? encoder.encode(needsActionConfiguration.normalized) {
            UserDefaults.standard.set(data, forKey: needsActionConfigurationStoreKey)
            UserDefaults.standard.removeObject(forKey: legacyNeedsActionConfigurationStoreKey)
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

    private func persistPostMergeWatches() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let payload = postMergeWatchesByKey.values.sorted { $0.createdAt > $1.createdAt }

        if let data = try? encoder.encode(payload) {
            UserDefaults.standard.set(data, forKey: postMergeWatchStoreKey)
        }
    }

    private func persistMergeMethodPreferences() {
        let payload = mergeMethodPreferenceByRepository.mapValues(\.rawValue)
        UserDefaults.standard.set(payload, forKey: mergeMethodPreferenceStoreKey)
    }

    private func syncIgnoredItems() {
        ignoredItems = ignoredItemsByKey.values.sorted { lhs, rhs in
            if lhs.ignoredAt == rhs.ignoredAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.ignoredAt > rhs.ignoredAt
        }
    }

    private func unignore(_ ignoredItems: [IgnoredAttentionSubject]) {
        let ignoredKeys = Set(ignoredItems.map(\.ignoreKey))
        guard !ignoredKeys.isEmpty else {
            return
        }

        for ignoreKey in ignoredKeys {
            ignoredItemsByKey[ignoreKey] = nil
        }

        syncIgnoredItems()
        persistIgnoredItems()
        trimIgnoreUndoState(removing: ignoredKeys)
        reconcileAttentionItemsFromSnapshot()
    }

    private func reconcileAttentionItemsFromSnapshot() {
        let visibleItems = AttentionItemVisibilityPolicy
            .excludingIgnoredSubjects(
                latestSnapshotAttentionItems,
                ignoredKeys: Set(ignoredItemsByKey.keys)
            )
        let aggregatedItems = AttentionCombinedViewPolicy
            .collapsingDuplicates(in: visibleItems)
        let projection = AttentionUpdateHistoryProjection.applying(
            persistedHistoryBySubjectKey: updateHistoryBySubjectKey,
            to: aggregatedItems
        )

        updateHistoryBySubjectKey = projection.historyBySubjectKey
        AttentionUpdateHistoryStore.persist(
            updateHistoryBySubjectKey,
            to: UserDefaults.standard,
            key: attentionUpdateHistoryStoreKey
        )
        attentionItems = projection.items.map(applyingLocalReadState)
        refreshNeedsActionItems()
    }

    private func applyPullRequestFocusSubjectRefresh(_ refresh: AttentionSubjectRefresh) {
        latestSnapshotAttentionItems = AttentionSubjectRefreshPolicy.applying(
            refresh,
            to: latestSnapshotAttentionItems
        )
        if let existingHistory = updateHistoryBySubjectKey[refresh.subjectKey] {
            let sanitizedHistory = AttentionUpdateHistoryPolicy.pruningInvalidWorkflowUpdates(
                existingHistory,
                mergedAt: refresh.mergedAt
            )
            updateHistoryBySubjectKey[refresh.subjectKey] = sanitizedHistory.isEmpty
                ? nil
                : sanitizedHistory
        }
        reconcileAttentionItemsFromSnapshot()
    }

    private func presentIgnoreUndo(for ignoredItems: [IgnoredAttentionSubject]) {
        ignoreUndoDismissTask?.cancel()

        let expiry = Date().addingTimeInterval(8)
        let ignoreUndoID = ignoredItems.map(\.ignoreKey).sorted().joined(separator: "|")
        ignoreUndoState = IgnoreUndoState(subjects: ignoredItems, expiresAt: expiry)

        ignoreUndoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self?.ignoreUndoState?.id == ignoreUndoID else {
                    return
                }

                self?.clearIgnoreUndoState()
            }
        }
    }

    private func trimIgnoreUndoState(removing ignoredKeys: Set<String>) {
        guard let ignoreUndoState else {
            return
        }

        let remainingSubjects = ignoreUndoState.subjects.filter { subject in
            !ignoredKeys.contains(subject.ignoreKey)
        }

        if remainingSubjects.count == ignoreUndoState.subjects.count {
            return
        }

        if remainingSubjects.isEmpty {
            clearIgnoreUndoState()
        } else {
            self.ignoreUndoState = IgnoreUndoState(
                subjects: remainingSubjects,
                expiresAt: ignoreUndoState.expiresAt
            )
        }
    }

    private func clearIgnoreUndoState() {
        ignoreUndoDismissTask?.cancel()
        ignoreUndoDismissTask = nil
        ignoreUndoState = nil
    }

    private func refreshNeedsActionItems() {
        needsActionItems = NeedsActionPolicy.matchingItems(
            in: attentionItems,
            configuration: needsActionConfiguration
        )
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

    private static func loadPostMergeWatches(
        from defaults: UserDefaults,
        key: String
    ) -> [String: PostMergeWatch] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let items = try? decoder.decode([PostMergeWatch].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    private static func loadMergeMethodPreferences(
        from defaults: UserDefaults,
        key: String
    ) -> [String: PullRequestMergeMethod] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: String] else {
            return [:]
        }

        return raw.reduce(into: [String: PullRequestMergeMethod]()) { partialResult, entry in
            guard let mergeMethod = PullRequestMergeMethod(rawValue: entry.value) else {
                return
            }

            partialResult[entry.key] = mergeMethod
        }
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
                .pullRequestMergeConflicts,
                .pullRequestFailedChecks,
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
        case .workflowRunning,
                .workflowSucceeded,
                .workflowFailed,
                .workflowApprovalRequired,
                .ciActivity:
            return 2
        }
    }

    private func preferredMergeMethod(
        for reference: PullRequestReference,
        allowedMethods: [PullRequestMergeMethod],
        fallback: PullRequestMergeMethod?
    ) -> PullRequestMergeMethod? {
        guard !allowedMethods.isEmpty else {
            return nil
        }

        if let storedPreference = mergeMethodPreferenceByRepository[mergeMethodPreferenceKey(for: reference)],
            allowedMethods.contains(storedPreference) {
            return storedPreference
        }

        if let fallback, allowedMethods.contains(fallback) {
            return fallback
        }

        return allowedMethods.first
    }

    private func mergeMethodPreferenceKey(for reference: PullRequestReference) -> String {
        reference.repository.lowercased()
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

    private static func loadNeedsActionConfiguration(
        from defaults: UserDefaults,
        key: String,
        legacyKey: String
    ) -> NeedsActionConfiguration {
        if let data = defaults.data(forKey: key),
            let configuration = try? JSONDecoder().decode(NeedsActionConfiguration.self, from: data) {
            return configuration.normalized
        }

        if let data = defaults.data(forKey: legacyKey),
            let legacyConfiguration = try? JSONDecoder().decode(
                LegacyNeedsActionConfiguration.self,
                from: data
            ) {
            return NeedsActionConfiguration.migrated(from: legacyConfiguration)
        }

        return .default
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

    private static func loadBooleanSetting(
        from defaults: UserDefaults,
        key: String
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    private func clearRateLimitState() {
        rateLimitBuckets = []
        rateLimit = nil
    }

    private func replaceRateLimitState(with snapshot: GitHubRateLimitSnapshot?) {
        rateLimitBuckets = snapshot?.buckets ?? []
        rateLimit = snapshot?.mostRestrictive
    }

    private func mergeRateLimitState(with snapshot: GitHubRateLimitSnapshot?) {
        guard let snapshot else {
            return
        }

        rateLimitBuckets = GitHubRateLimit.mergingCollections(rateLimitBuckets, with: snapshot.buckets)
        rateLimit = GitHubRateLimit.mostRestrictive(in: rateLimitBuckets)
    }

    private func mergeRateLimitState(with rateLimit: GitHubRateLimit?) {
        guard let rateLimit else {
            return
        }

        rateLimitBuckets = GitHubRateLimit.mergingCollections(rateLimitBuckets, with: [rateLimit])
        self.rateLimit = GitHubRateLimit.mostRestrictive(in: rateLimitBuckets)
    }

    private func effectiveAutomaticPollInterval(relativeTo referenceDate: Date) -> Int {
        rateLimit?.minimumAutomaticRefreshInterval(
            userConfiguredSeconds: pollIntervalSeconds,
            now: referenceDate
        ) ?? pollIntervalSeconds
    }

    private func effectiveFocusedPullRequestWatchInterval(relativeTo referenceDate: Date) -> Int {
        rateLimit?.minimumAutomaticRefreshInterval(
            userConfiguredSeconds: focusedPullRequestWatchIntervalSeconds,
            now: referenceDate
        ) ?? focusedPullRequestWatchIntervalSeconds
    }

    private func effectiveQueuedPostMergeWatchInterval(relativeTo referenceDate: Date) -> Int {
        rateLimit?.minimumAutomaticRefreshInterval(
            userConfiguredSeconds: queuedPostMergeWatchIntervalSeconds,
            now: referenceDate
        ) ?? queuedPostMergeWatchIntervalSeconds
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
        latestSnapshotAttentionItems = fixture.attentionItems
        attentionItems = fixture.attentionItems
        needsActionItems = NeedsActionPolicy.matchingItems(
            in: fixture.attentionItems,
            configuration: needsActionConfiguration
        )
        lastUpdated = fixture.lastUpdated
        lastError = nil
        isResolvingInitialContent = false
        gitHubCLIAvailable = false
        usingGitHubCLIToken = false
        isValidatingToken = false
        clearRateLimitState()
        knownLatestUpdateKeyBySubjectKey = Dictionary(
            uniqueKeysWithValues: fixture.attentionItems.map { ($0.subjectKey, $0.updateKey) }
        )
        ignoredItemsByKey = [:]
        ignoredItems = []
        readStateBySubjectKey = [:]
        updateHistoryBySubjectKey = [:]
        autoMarkReadSetting = fixture.autoMarkReadSetting
        notifyOnSelfTriggeredUpdates = false
        showsDebugRateLimitDetails = false
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
            subjectKey: "https://github.com/\(repository)/pull/1",
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
            subjectKey: "https://github.com/\(repository)/pull/2",
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

import Foundation
import Network
import SwiftUI

enum AppConnectivityStatus: Equatable, Sendable {
    case unknown
    case online
    case offline
}

enum AppStartupUnavailableState: Equatable, Sendable {
    case connectionRequired
    case offline

    var title: String {
        switch self {
        case .connectionRequired:
            return "GitHub Connection Required"
        case .offline:
            return "You're Offline"
        }
    }

    var description: String {
        switch self {
        case .connectionRequired:
            return "Open Settings to connect GitHub with either GitHub CLI or a personal access token."
        case .offline:
            return "Octowatch can't reach GitHub while your Mac is offline. It will retry automatically when the connection comes back."
        }
    }

    var systemImage: String {
        switch self {
        case .connectionRequired:
            return "person.crop.circle.badge.exclamationmark"
        case .offline:
            return "wifi.slash"
        }
    }
}

enum AuthenticationStartupGuideContext: Equatable, Sendable {
    case onboarding
    case recovery
}

enum SettingsAuthenticationSource: Equatable, Sendable {
    case githubCLI
    case personalAccessToken
}

enum SettingsNavigationTarget: Equatable, Sendable {
    case authentication(preferredSource: SettingsAuthenticationSource)
}

enum GitHubCLIAuthStatus: Equatable, Sendable {
    case checking
    case notInstalled
    case tokenUnavailable
    case tokenRejected
    case ready

    var stateLabel: String {
        switch self {
        case .checking:
            return "Checking"
        case .notInstalled:
            return "Not Found"
        case .tokenUnavailable:
            return "Needs Login"
        case .tokenRejected:
            return "Needs Attention"
        case .ready:
            return "Ready"
        }
    }

    var installationLabel: String {
        isDetected ? "Found" : "Not Found"
    }

    var detail: String {
        switch self {
        case .checking:
            return "Octowatch is checking whether GitHub CLI can provide a token."
        case .notInstalled:
            return "GitHub CLI is not installed on this Mac."
        case .tokenUnavailable:
            return "GitHub CLI is installed, but `gh auth token` did not return a usable token."
        case .tokenRejected:
            return "GitHub CLI returned a token, but GitHub rejected it for Octowatch."
        case .ready:
            return "GitHub CLI is installed and can provide a validated token."
        }
    }

    var isDetected: Bool {
        self != .notInstalled
    }
}

enum PersonalAccessTokenAuthStatus: Equatable, Sendable {
    case unavailable
    case storedInKeychain
    case rejected

    var stateLabel: String {
        switch self {
        case .unavailable:
            return "Not Set Up"
        case .storedInKeychain:
            return "Saved in Keychain"
        case .rejected:
            return "Needs Replacement"
        }
    }

    var detail: String {
        switch self {
        case .unavailable:
            return "No saved personal access token is currently available."
        case .storedInKeychain:
            return "A personal access token is saved in Keychain and can be reused on launch."
        case .rejected:
            return "A saved personal access token was rejected and needs to be replaced."
        }
    }
}

struct AuthenticationStartupGuide: Equatable, Sendable {
    let context: AuthenticationStartupGuideContext
    let gitHubCLIStatus: GitHubCLIAuthStatus
    let personalAccessTokenStatus: PersonalAccessTokenAuthStatus

    var title: String {
        switch context {
        case .onboarding:
            return "Welcome to Octowatch"
        case .recovery:
            return "Connect GitHub"
        }
    }

    var requiresManualIntervention: Bool {
        gitHubCLIStatus != .ready && personalAccessTokenStatus != .storedInKeychain
    }

    var summary: String {
        switch context {
        case .onboarding:
            switch (gitHubCLIStatus, personalAccessTokenStatus) {
            case (.ready, _):
                return "GitHub CLI was found and Octowatch will use it to authenticate."
            case (_, .storedInKeychain):
                return "A saved personal access token was found in Keychain and is ready to use."
            case (.notInstalled, _):
                return "GitHub CLI was not found. Finish setup with a personal access token."
            case (.tokenUnavailable, _):
                return "GitHub CLI was found, but Octowatch still needs manual setup."
            case (.tokenRejected, _):
                return "GitHub CLI was found, but its token needs attention."
            case (.checking, _):
                return "Octowatch is still checking how to connect GitHub."
            }
        case .recovery:
            switch gitHubCLIStatus {
            case .notInstalled:
                return "GitHub CLI was not found. Manual setup is required."
            case .tokenUnavailable:
                return "GitHub CLI was found, but Octowatch still needs manual setup."
            case .tokenRejected:
                return "GitHub CLI was found, but its token needs attention."
            case .checking:
                return "Octowatch is still checking how to connect GitHub."
            case .ready:
                return "GitHub CLI is ready."
            }
        }
    }

    var manualInterventionLabel: String {
        switch context {
        case .onboarding:
            return requiresManualIntervention ? "Manual Intervention" : "Authentication"
        case .recovery:
            return "Manual Intervention"
        }
    }

    var manualInterventionDetail: String {
        if context == .onboarding {
            switch (gitHubCLIStatus, personalAccessTokenStatus) {
            case (.ready, _):
                return "Octowatch will reuse your GitHub CLI login unless you switch to a personal access token."
            case (_, .storedInKeychain):
                return "Octowatch can start with the saved personal access token, or you can switch to GitHub CLI later."
            default:
                break
            }
        }

        switch (gitHubCLIStatus, personalAccessTokenStatus) {
        case (_, .rejected):
            return "Update the saved personal access token or paste a new one in Settings."
        case (.notInstalled, _):
            return "Create a personal access token and connect it in Octowatch."
        case (.tokenUnavailable, _):
            return "Sign in with `gh auth login`, or set up a personal access token instead."
        case (.tokenRejected, _):
            return "Re-authenticate GitHub CLI with `gh auth login`, or use a personal access token."
        case (.checking, _):
            return "Wait for the authentication check to finish."
        case (.ready, _):
            return "No manual action is required."
        }
    }

    var nextSteps: [String] {
        var steps = [String]()

        if context == .onboarding && !requiresManualIntervention {
            return [
                "Continue with the detected authentication to finish setup.",
                "Open Authentication settings if you want to switch to a personal access token instead."
            ]
        }

        switch gitHubCLIStatus {
        case .notInstalled:
            steps.append("Create a personal access token on GitHub.")
        case .tokenUnavailable:
            steps.append("Run `gh auth login` if you want Octowatch to reuse GitHub CLI.")
            steps.append("Or create a personal access token on GitHub instead.")
        case .tokenRejected:
            steps.append("Run `gh auth login` to refresh GitHub CLI credentials.")
            steps.append("Or create a personal access token on GitHub instead.")
        case .checking, .ready:
            break
        }

        if personalAccessTokenStatus != .storedInKeychain || gitHubCLIStatus != .ready {
            steps.append("Grant read access to notifications, pull requests, issues, and actions.")
            steps.append("Open Authentication settings and paste the token.")
            steps.append("Leave Keychain storage on if you want Octowatch to reuse the token on future launches.")
        }

        return steps
    }
}

enum GitHubPersonalAccessTokenSetup {
    static let settingsURL = URL(string: "https://github.com/settings/tokens")!
    static let recommendedScopes = [
        "Notifications",
        "Pull requests",
        "Issues",
        "Actions"
    ]
}

@MainActor
final class AppModel: ObservableObject {
    private enum TokenSource: Sendable {
        case githubCLI
        case personalAccessTokenInput
        case personalAccessTokenKeychain
    }

    private struct PendingTokenCandidate: Sendable {
        let token: String
        let source: TokenSource
    }

    static let shared = AppModel()

    @Published private(set) var attentionItems: [AttentionItem] = []
    @Published private(set) var pullRequestDashboard = PullRequestDashboard.empty
    @Published private(set) var issueDashboard = IssueDashboard.empty
    @Published private(set) var isPullRequestDashboardRefreshing = false
    @Published private(set) var isIssueDashboardRefreshing = false
    @Published private(set) var pullRequestDashboardLastUpdated: Date?
    @Published private(set) var issueDashboardLastUpdated: Date?
    @Published private(set) var pullRequestDashboardLastError: String?
    @Published private(set) var issueDashboardLastError: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var rateLimit: GitHubRateLimit?
    @Published private(set) var rateLimitBuckets: [GitHubRateLimit] = []
    @Published private(set) var connectivityStatus: AppConnectivityStatus = .unknown
    @Published private(set) var storesPersonalAccessTokenInKeychain = true
    @Published private(set) var usingKeychainStoredPersonalAccessToken = false
    @Published private(set) var gitHubCLIAuthStatus: GitHubCLIAuthStatus = .checking
    @Published private(set) var personalAccessTokenAuthStatus: PersonalAccessTokenAuthStatus = .unavailable
    @Published private(set) var hasCompletedInitialSetup = true
    @Published private(set) var settingsNavigationTarget: SettingsNavigationTarget?

    @Published var tokenInput = ""
    @Published private(set) var isResolvingInitialContent = true
    @Published private(set) var gitHubCLIAvailable = false
    @Published private(set) var usingGitHubCLIToken = false
    @Published private(set) var isValidatingToken = false
    @Published private(set) var ignoredItems: [IgnoredAttentionSubject] = []
    @Published private(set) var ignoreUndoState: IgnoreUndoState?
    @Published private(set) var snoozedItems: [SnoozedAttentionSubject] = []
    @Published private(set) var snoozeUndoState: SnoozeUndoState?
    @Published private(set) var pollIntervalSeconds = 60
    @Published private(set) var autoMarkReadSetting: AutoMarkReadSetting = .threeSeconds
    @Published private(set) var notifyOnSelfTriggeredUpdates = false
    @Published private(set) var showsMenuBarIcon = true
    @Published private(set) var pullRequestWatchRevision = 0
    @Published private(set) var showsDebugRateLimitDetails = false
    @Published private(set) var inboxSectionConfig: InboxSectionConfiguration = .default
    @Published private(set) var inboxSections: [InboxSectionPolicy.SectionResult] = []

    var inboxSectionItems: [AttentionItem] {
        inboxSections.flatMap(\.items)
    }

    private let readStateStoreKey = "attention-subject-read-state-v2"
    private let ignoredSubjectStoreKey = "ignored-attention-subjects-v2"
    private let legacyIgnoredSubjectStoreKey = "ignored-attention-subjects-v1"
    private let snoozedSubjectStoreKey = "snoozed-attention-subjects-v1"
    private let pollIntervalStoreKey = "poll-interval-seconds-v1"
    private let autoMarkReadStoreKey = "auto-mark-read-setting-v1"
    private let notifyOnSelfTriggeredUpdatesStoreKey = "notify-on-self-triggered-updates-v1"
    private let showsMenuBarIconStoreKey = "shows-menu-bar-icon-v1"
    private let debugRateLimitDetailsStoreKey = "debug-rate-limit-details-v1"
    private let storesPersonalAccessTokenInKeychainStoreKey =
        "stores-personal-access-token-in-keychain-v1"
    private let completedInitialSetupStoreKey = "completed-initial-setup-v1"
    private let inboxSectionConfigStoreKey = "needs-action-configuration-v3"
    private let legacyInboxSectionConfigStoreKey = "needs-action-configuration-v2"
    private let legacyInboxSectionConfigStoreKeyV1 = "needs-action-configuration-v1"
    private let notificationScanStateStoreKey = "notification-scan-state-v1"
    private let teamMembershipStoreKey = "team-membership-cache-v1"
    private let postMergeWatchStoreKey = "post-merge-watches-v1"
    private let mergeMethodPreferenceStoreKey = "merge-method-preferences-v1"
    private let acknowledgedWorkflowsStoreKey = "acknowledged-workflows-v1"
    private let attentionUpdateHistoryStoreKey = "attention-update-history-v1"
    private let keychainStore = KeychainStore(service: "app.octowatch.auth")
    private let legacyKeychainStores = [
        KeychainStore(service: "dev.octowatch.app.auth")
    ]
    private let personalAccessTokenKeychainAccount = "personal-access-token"
    private let client = GitHubClient()
    private let workflowRunCache = WorkflowRunCache()
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
    private var latestSnapshotPullRequestDashboard = PullRequestDashboard.empty
    private var latestSnapshotIssueDashboard = IssueDashboard.empty
    private var knownLatestUpdateKeyBySubjectKey = [String: String]()
    private var notificationScanState = NotificationScanState.default
    private var teamMembershipCache = TeamMembershipCache.default
    private var postMergeWatchesByKey = [String: PostMergeWatch]()
    private var pullRequestFocusCache = [String: PullRequestFocusCacheEntry]()
    private var watchedPullRequestKey: String?
    private var watchedPullRequestState: PullRequestLiveWatchState?
    private var ignoredItemsByKey = [String: IgnoredAttentionSubject]()
    private var snoozedItemsByKey = [String: SnoozedAttentionSubject]()
    private var acknowledgedWorkflows = [String: AcknowledgedWorkflowState]()
    private var mergeMethodPreferenceByRepository = [String: PullRequestMergeMethod]()
    private var ignoreUndoDismissTask: Task<Void, Never>?
    private var snoozeUndoDismissTask: Task<Void, Never>?
    private var snoozeWakeTask: Task<Void, Never>?
    private var readStateBySubjectKey: [String: Date] = [:]
    private var updateHistoryBySubjectKey = [String: [AttentionUpdate]]()
    private var suppressedTransitionNotificationKeys = Set<String>()
    private var pendingForcedRefresh = false
    private var pendingTokenCandidate: PendingTokenCandidate?
    private var connectivityMonitor: NWPathMonitor?
    private let connectivityMonitorQueue = DispatchQueue(
        label: "app.octowatch.macos.connectivity"
    )
    private var connectivityRecoveryTask: Task<Void, Never>?
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    init() {
        let hadExistingPersistentState = Self.hasExistingPersistentState()
        gitHubCLIAvailable = GitHubCLITokenProvider.isInstalled
        gitHubCLIAuthStatus = gitHubCLIAvailable ? .checking : .notInstalled
        hasCompletedInitialSetup = Self.loadBooleanSetting(
            from: UserDefaults.standard,
            key: completedInitialSetupStoreKey,
            defaultValue: hadExistingPersistentState
        )
        storesPersonalAccessTokenInKeychain = Self.loadBooleanSetting(
            from: UserDefaults.standard,
            key: storesPersonalAccessTokenInKeychainStoreKey,
            defaultValue: true
        )
        personalAccessTokenAuthStatus = storesPersonalAccessTokenInKeychain &&
            storedPersonalAccessToken() != nil
            ? .storedInKeychain
            : .unavailable
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
        showsMenuBarIcon = Self.loadBooleanSetting(
            from: UserDefaults.standard,
            key: showsMenuBarIconStoreKey,
            defaultValue: true
        )
        showsDebugRateLimitDetails = Self.loadBooleanSetting(
            from: UserDefaults.standard,
            key: debugRateLimitDetailsStoreKey
        )
        inboxSectionConfig = Self.loadInboxSectionConfiguration(
            from: UserDefaults.standard,
            key: inboxSectionConfigStoreKey,
            legacyKey: legacyInboxSectionConfigStoreKey,
            legacyKeyV1: legacyInboxSectionConfigStoreKeyV1
        )
        if UserDefaults.standard.data(forKey: inboxSectionConfigStoreKey) == nil {
            persistInboxSectionConfiguration()
        }
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
        snoozedItemsByKey = Self.loadSnoozedItems(
            from: UserDefaults.standard,
            key: snoozedSubjectStoreKey
        )
        syncIgnoredItems()
        syncSnoozedItems()
        persistSnoozedItems()
        loadAcknowledgedWorkflows()
        scheduleSnoozeWakeIfNeeded()

        if let launchFixture = LaunchFixture.load(from: ProcessInfo.processInfo.environment) {
            applyLaunchFixture(launchFixture)
            return
        }

        startConnectivityMonitoring()

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
        snoozeUndoDismissTask?.cancel()
        snoozeWakeTask?.cancel()
        connectivityRecoveryTask?.cancel()
        connectivityMonitor?.cancel()
    }

    var hasToken: Bool {
        !(token ?? "").isEmpty
    }

    var viewerLogin: String? {
        userLogin
    }

    var hasStoredPersonalAccessToken: Bool {
        personalAccessTokenAuthStatus == .storedInKeychain
    }

    var usingPersonalAccessToken: Bool {
        hasToken && !usingGitHubCLIToken
    }

    var showsInitialSetupGuide: Bool {
        !isResolvingInitialContent && !hasCompletedInitialSetup
    }

    var initialSetupGuide: AuthenticationStartupGuide? {
        guard showsInitialSetupGuide else {
            return nil
        }

        return AuthenticationStartupGuide(
            context: .onboarding,
            gitHubCLIStatus: gitHubCLIAuthStatus,
            personalAccessTokenStatus: personalAccessTokenAuthStatus
        )
    }

    var authenticationStartupGuide: AuthenticationStartupGuide? {
        guard startupUnavailableState == .connectionRequired else {
            return nil
        }

        return AuthenticationStartupGuide(
            context: .recovery,
            gitHubCLIStatus: gitHubCLIAuthStatus,
            personalAccessTokenStatus: personalAccessTokenAuthStatus
        )
    }

    var startupUnavailableState: AppStartupUnavailableState? {
        guard !isResolvingInitialContent, !hasToken else {
            return nil
        }

        if connectivityStatus == .offline, canRecoverConnectionWithoutOpeningSettings {
            return .offline
        }

        return .connectionRequired
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

    func pullRequestDashboardItems(for filter: PullRequestDashboardFilter) -> [AttentionItem] {
        pullRequestDashboard[filter]
    }

    func issueDashboardItems(for filter: IssueDashboardFilter) -> [AttentionItem] {
        issueDashboard[filter]
    }

    var actionableAttentionItems: [AttentionItem] {
        AttentionItemVisibilityPolicy.excludingHistoricalLogEntries(combinedAttentionItems)
    }

    var relativeLastUpdated: String {
        relativeLastUpdated(relativeTo: Date())
    }

    func relativeLastUpdated(relativeTo referenceDate: Date) -> String {
        relativeUpdateLabel(for: lastUpdated, relativeTo: referenceDate)
    }

    func relativePullRequestDashboardLastUpdated(relativeTo referenceDate: Date) -> String {
        relativeUpdateLabel(for: pullRequestDashboardLastUpdated, relativeTo: referenceDate)
    }

    func relativeIssueDashboardLastUpdated(relativeTo referenceDate: Date) -> String {
        relativeUpdateLabel(for: issueDashboardLastUpdated, relativeTo: referenceDate)
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

    private func relativeUpdateLabel(for updatedAt: Date?, relativeTo referenceDate: Date) -> String {
        guard let updatedAt else {
            return "Not refreshed yet"
        }

        if abs(updatedAt.timeIntervalSince(referenceDate)) < 1 {
            return "Updated now"
        }

        let relative = relativeDateFormatter.localizedString(
            for: updatedAt,
            relativeTo: referenceDate
        )
        return "Updated \(relative)"
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

    func setShowsMenuBarIcon(_ value: Bool) {
        guard showsMenuBarIcon != value else {
            return
        }

        showsMenuBarIcon = value
        UserDefaults.standard.set(value, forKey: showsMenuBarIconStoreKey)
    }

    func setInboxRuleEnabled(_ ruleID: UUID, isEnabled: Bool) {
        guard let existingRule = inboxSectionConfig.rules.first(where: { $0.id == ruleID }) else {
            return
        }

        var updatedRule = existingRule
        updatedRule.isEnabled = isEnabled
        let updatedConfiguration = inboxSectionConfig.replacing(updatedRule)
        guard updatedConfiguration != inboxSectionConfig else {
            return
        }

        inboxSectionConfig = updatedConfiguration
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    @discardableResult
    func saveInboxRule(_ rule: InboxSectionRule) -> InboxSectionRule {
        let normalizedRule = rule.normalized
        let updatedConfiguration = inboxSectionConfig.replacing(normalizedRule)
        inboxSectionConfig = updatedConfiguration
        refreshInboxSections()
        persistInboxSectionConfiguration()
        return normalizedRule
    }

    func duplicateInboxRule(_ ruleID: UUID) {
        let updatedConfiguration = inboxSectionConfig.duplicatingRule(id: ruleID)
        guard updatedConfiguration != inboxSectionConfig else {
            return
        }

        inboxSectionConfig = updatedConfiguration
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    func deleteInboxRule(_ ruleID: UUID) {
        let updatedConfiguration = inboxSectionConfig.removingRule(id: ruleID)
        guard updatedConfiguration != inboxSectionConfig else {
            return
        }

        inboxSectionConfig = updatedConfiguration
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    func resetInboxSections() {
        guard inboxSectionConfig != .default else {
            return
        }

        inboxSectionConfig = .default
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    // MARK: - Section CRUD

    func addInboxSection(name: String) {
        let section = InboxSection(name: name, rules: [])
        inboxSectionConfig = inboxSectionConfig.addingSection(section)
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    func deleteInboxSection(id: UUID) {
        inboxSectionConfig = inboxSectionConfig.removingSection(id: id)
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    func renameInboxSection(id: UUID, name: String) {
        guard var section = inboxSectionConfig.sections.first(where: { $0.id == id }) else {
            return
        }
        section.name = name
        inboxSectionConfig = inboxSectionConfig.replacing(section)
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    func moveInboxSection(id: UUID, direction: Int) {
        let updatedConfiguration = inboxSectionConfig.movingSection(id: id, direction: direction)
        guard updatedConfiguration != inboxSectionConfig else {
            return
        }

        inboxSectionConfig = updatedConfiguration
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    func reorderInboxSections(fromOffsets: IndexSet, toOffset: Int) {
        var sections = inboxSectionConfig.sections
        sections.move(fromOffsets: fromOffsets, toOffset: toOffset)
        inboxSectionConfig = InboxSectionConfiguration(sections: sections)
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    func reorderInboxRules(inSectionID sectionID: UUID, fromOffsets: IndexSet, toOffset: Int) {
        guard let index = inboxSectionConfig.sections.firstIndex(where: { $0.id == sectionID }) else {
            return
        }
        var sections = inboxSectionConfig.sections
        sections[index].rules.move(fromOffsets: fromOffsets, toOffset: toOffset)
        inboxSectionConfig = InboxSectionConfiguration(sections: sections)
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    func toggleInboxSection(id: UUID) {
        guard var section = inboxSectionConfig.sections.first(where: { $0.id == id }) else {
            return
        }
        section.isEnabled.toggle()
        inboxSectionConfig = inboxSectionConfig.replacing(section)
        refreshInboxSections()
        persistInboxSectionConfiguration()
    }

    @discardableResult
    func addRuleToSection(sectionID: UUID, itemKind: InboxRuleItemKind = .pullRequest) -> InboxSectionRule {
        let rule = InboxSectionRule.newCustom(itemKind: itemKind)
        inboxSectionConfig = inboxSectionConfig.addingRule(rule, toSectionID: sectionID)
        refreshInboxSections()
        persistInboxSectionConfiguration()
        return rule
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
            clearPersonalAccessToken()
            return false
        }

        let saved = await validateAndApplyToken(cleaned, source: .personalAccessTokenInput)
        if saved {
            tokenInput = ""
            completeInitialSetup()
        }
        return saved
    }

    func clearToken() {
        let existingSubjectKeys = Array(attentionItems.map(\.subjectKey))

        token = nil
        tokenInput = ""
        usingGitHubCLIToken = false
        usingKeychainStoredPersonalAccessToken = false
        pendingTokenCandidate = nil
        clearStoredPersonalAccessToken()
        latestSnapshotAttentionItems = []
        latestSnapshotPullRequestDashboard = .empty
        latestSnapshotIssueDashboard = .empty
        attentionItems = []
        pullRequestDashboard = .empty
        issueDashboard = .empty
        isPullRequestDashboardRefreshing = false
        isIssueDashboardRefreshing = false
        pullRequestDashboardLastUpdated = nil
        issueDashboardLastUpdated = nil
        pullRequestDashboardLastError = nil
        issueDashboardLastError = nil
        inboxSections = []
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

    func clearPersonalAccessToken() {
        tokenInput = ""
        clearStoredPersonalAccessToken()

        guard usingPersonalAccessToken else {
            return
        }

        clearToken()
    }

    func completeInitialSetup() {
        guard !hasCompletedInitialSetup else {
            return
        }

        hasCompletedInitialSetup = true
        UserDefaults.standard.set(true, forKey: completedInitialSetupStoreKey)
    }

    func requestAuthenticationSettings(preferredSource: SettingsAuthenticationSource) {
        settingsNavigationTarget = .authentication(preferredSource: preferredSource)
    }

    func consumeSettingsNavigationTarget() {
        settingsNavigationTarget = nil
    }

    func reloadTokenFromGitHubCLI() async -> Bool {
        let reloaded = await importTokenFromGitHubCLIIfAvailable(force: true)
        if reloaded {
            completeInitialSetup()
        }
        return reloaded
    }

    func setStoresPersonalAccessTokenInKeychain(_ value: Bool) {
        guard storesPersonalAccessTokenInKeychain != value else {
            return
        }

        storesPersonalAccessTokenInKeychain = value
        UserDefaults.standard.set(value, forKey: storesPersonalAccessTokenInKeychainStoreKey)

        if value {
            if usingPersonalAccessToken, let token {
                persistStoredPersonalAccessToken(token)
            } else {
                personalAccessTokenAuthStatus = storedPersonalAccessToken() != nil
                    ? .storedInKeychain
                    : .unavailable
            }
        } else {
            clearStoredPersonalAccessToken()
        }
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

    func retryConnection() {
        connectivityRecoveryTask?.cancel()
        connectivityRecoveryTask = Task { [weak self] in
            await self?.attemptConnectionRecovery(forceTokenReload: true)
        }
    }

    func ensurePullRequestDashboardLoaded() async {
        guard pullRequestDashboardLastUpdated == nil else {
            return
        }

        await refreshPullRequestDashboard(force: false)
    }

    func ensureIssueDashboardLoaded() async {
        guard issueDashboardLastUpdated == nil else {
            return
        }

        await refreshIssueDashboard(force: false)
    }

    func refreshPullRequestDashboard(force: Bool = true) async {
        guard hasToken, let token else {
            return
        }

        guard !isPullRequestDashboardRefreshing else {
            return
        }

        if !force, pullRequestDashboardLastUpdated != nil {
            return
        }

        guard let login = userLogin else {
            return
        }

        isPullRequestDashboardRefreshing = true
        defer { isPullRequestDashboardRefreshing = false }

        do {
            let result = try await client.fetchPullRequestDashboard(
                token: token,
                login: login,
                teamMembershipCache: teamMembershipCache
            )
            userLogin = result.login
            teamMembershipCache = result.teamMembershipCache.normalized
            persistTeamMembershipCache()
            mergeRateLimitState(with: result.rateLimits)
            latestSnapshotPullRequestDashboard = result.dashboard
            pullRequestDashboardLastUpdated = Date()
            pullRequestDashboardLastError = nil
            reconcileVisibleContentFromSnapshot()
        } catch {
            if let clientError = error as? GitHubClientError,
                case let .rateLimited(rateLimit) = clientError {
                mergeRateLimitState(with: rateLimit)
            }
            recordConnectivityFailureIfNeeded(for: error)
            pullRequestDashboardLastError = userFacingRefreshError(for: error)
        }
    }

    func refreshIssueDashboard(force: Bool = true) async {
        guard hasToken, let token else {
            return
        }

        guard !isIssueDashboardRefreshing else {
            return
        }

        if !force, issueDashboardLastUpdated != nil {
            return
        }

        guard let login = userLogin else {
            return
        }

        isIssueDashboardRefreshing = true
        defer { isIssueDashboardRefreshing = false }

        do {
            let result = try await client.fetchIssueDashboard(
                token: token,
                login: login
            )
            userLogin = result.login
            mergeRateLimitState(with: result.rateLimits)
            latestSnapshotIssueDashboard = result.dashboard
            issueDashboardLastUpdated = Date()
            issueDashboardLastError = nil
            reconcileVisibleContentFromSnapshot()
        } catch {
            if let clientError = error as? GitHubClientError,
                case let .rateLimited(rateLimit) = clientError {
                mergeRateLimitState(with: rateLimit)
            }
            recordConnectivityFailureIfNeeded(for: error)
            issueDashboardLastError = userFacingRefreshError(for: error)
        }
    }

    func forceRefresh(item: AttentionItem? = nil) async {
        if let item, item.pullRequestReference != nil {
            pullRequestFocusCache[item.ignoreKey] = nil
            pullRequestWatchRevision &+= 1
        }

        await refresh(force: true)

        if let item, !item.supportsReadState {
            switch item.stream {
            case .pullRequests:
                await refreshPullRequestDashboard(force: true)
            case .issues:
                await refreshIssueDashboard(force: true)
            case .notifications:
                break
            }
        }
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

    func cachedPullRequestFocus(for item: AttentionItem) -> PullRequestFocus? {
        let cacheKey = item.ignoreKey
        return pullRequestFocusCache[cacheKey]?.focus
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
            sourceType: item.pullRequestFocusSourceType,
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

    func markPullRequestReadyForReview(for item: AttentionItem) async throws {
        guard let reference = item.pullRequestReference, let token else {
            throw GitHubClientError.invalidResponse
        }

        let rateLimits = try await client.markPullRequestReadyForReview(
            token: token,
            reference: reference
        )
        mergeRateLimitState(with: rateLimits)
        pullRequestFocusCache[item.ignoreKey] = nil
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

    func acknowledgeWorkflow(for item: AttentionItem) {
        let key = item.subjectKey
        let runID = item.latestSourceID
        if let existing = acknowledgedWorkflows[key] {
            acknowledgedWorkflows[key] = existing.adding(runID: runID)
        } else {
            acknowledgedWorkflows[key] = AcknowledgedWorkflowState(
                subjectKey: key,
                acknowledgedRunIDs: [runID],
                acknowledgedAt: Date()
            )
        }
        persistAcknowledgedWorkflows()
        refreshInboxSections()
    }

    func snooze(_ item: AttentionItem, preset: AttentionSnoozePreset) {
        snooze([item], preset: preset)
    }

    func snooze(_ items: [AttentionItem], preset: AttentionSnoozePreset) {
        let now = Date()
        let snoozedUntil = preset.snoozedUntil(from: now)
        var snoozedSummaries = [SnoozedAttentionSubject]()
        var snoozedKeys = Set<String>()

        for item in items {
            guard snoozedKeys.insert(item.ignoreKey).inserted else {
                continue
            }

            let summary = preferredSnoozedSummary(for: item, snoozedAt: now, snoozedUntil: snoozedUntil)
            snoozedItemsByKey[item.ignoreKey] = summary
            snoozedSummaries.append(summary)
            ignoredItemsByKey[item.ignoreKey] = nil
        }

        guard !snoozedSummaries.isEmpty else {
            return
        }

        syncIgnoredItems()
        persistIgnoredItems()
        syncSnoozedItems()
        persistSnoozedItems()
        presentSnoozeUndo(for: snoozedSummaries)
        notifier.removeSubjectNotifications(subjectKeys: Array(snoozedKeys))
        scheduleSnoozeWakeIfNeeded()
        reconcileVisibleContentFromSnapshot()
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
            snoozedItemsByKey[item.ignoreKey] = nil
            ignoredSummaries.append(summary)
        }

        guard !ignoredSummaries.isEmpty else {
            return
        }

        syncIgnoredItems()
        persistIgnoredItems()
        syncSnoozedItems()
        persistSnoozedItems()
        trimSnoozeUndoState(removing: ignoredKeys)
        presentIgnoreUndo(for: ignoredSummaries)
        notifier.removeSubjectNotifications(subjectKeys: Array(ignoredKeys))
        scheduleSnoozeWakeIfNeeded()
        reconcileVisibleContentFromSnapshot()
    }

    func unignore(_ ignoredItem: IgnoredAttentionSubject) {
        unignore([ignoredItem])
    }

    func unsnooze(_ snoozedItem: SnoozedAttentionSubject) {
        unsnooze([snoozedItem])
    }

    func undoRecentIgnore() {
        guard let ignoreUndoState else {
            return
        }

        unignore(ignoreUndoState.subjects)
    }

    func undoRecentSnooze() {
        guard let snoozeUndoState else {
            return
        }

        unsnooze(snoozeUndoState.subjects)
    }

    func dismissIgnoreUndo() {
        clearIgnoreUndoState()
    }

    func dismissRecentSnooze() {
        clearSnoozeUndoState()
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

    private var canRecoverConnectionWithoutOpeningSettings: Bool {
        pendingTokenCandidate != nil || gitHubCLIAvailable || hasStoredPersonalAccessToken
    }

    private func startConnectivityMonitoring() {
        let monitor = NWPathMonitor()
        connectivityMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handleConnectivityUpdate(path)
            }
        }
        monitor.start(queue: connectivityMonitorQueue)
    }

    private func handleConnectivityUpdate(_ path: NWPath) {
        let previousStatus = connectivityStatus
        let nextStatus: AppConnectivityStatus = switch path.status {
        case .satisfied:
            .online
        case .requiresConnection, .unsatisfied:
            .offline
        @unknown default:
            .unknown
        }

        guard nextStatus != previousStatus else {
            return
        }

        connectivityStatus = nextStatus

        guard nextStatus == .online else {
            return
        }

        connectivityRecoveryTask?.cancel()
        connectivityRecoveryTask = Task { [weak self] in
            await self?.attemptConnectionRecovery(forceTokenReload: false)
        }
    }

    private func attemptConnectionRecovery(forceTokenReload: Bool) async {
        if let pendingTokenCandidate {
            _ = await validateAndApplyToken(
                pendingTokenCandidate.token,
                source: pendingTokenCandidate.source
            )
            return
        }

        if !hasToken {
            let loadedFromCLI = await importTokenFromGitHubCLIIfAvailable(force: forceTokenReload)
            if loadedFromCLI {
                return
            }

            _ = await importStoredPersonalAccessTokenIfAvailable()
            return
        }

        await refresh(force: true)

        if pullRequestDashboardLastError != nil {
            await refreshPullRequestDashboard(force: true)
        }

        if issueDashboardLastError != nil {
            await refreshIssueDashboard(force: true)
        }
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
                teamMembershipCache: teamMembershipCache,
                workflowRunCache: workflowRunCache
            )
            userLogin = snapshot.login
            replaceRateLimitState(with: snapshot.rateLimits)
            notificationScanState = snapshot.notificationScanState.normalized
            teamMembershipCache = snapshot.teamMembershipCache.normalized
            persistNotificationScanState()
            persistTeamMembershipCache()
            let snapshotWorkflowSubjectKeys = Set(
                snapshot.attentionItems
                    .filter { $0.type.isWorkflowActivityType }
                    .map(\.subjectKey)
            )
            let preservedSupplementalItems = latestSnapshotAttentionItems.filter { item in
                item.id.hasPrefix(AttentionSubjectRefresh.localSupplementalItemIDPrefix)
                    && !snapshotWorkflowSubjectKeys.contains(item.subjectKey)
            }
            latestSnapshotAttentionItems = snapshot.attentionItems + preservedSupplementalItems
            reconcileVisibleContentFromSnapshot()
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
            recordConnectivityFailureIfNeeded(for: error)
            lastError = userFacingRefreshError(for: error)
        }

        if isResolvingInitialContent {
            isResolvingInitialContent = false
        }
    }

    private func bootstrapToken() async {
        let importedToken = await importTokenFromGitHubCLIIfAvailable(force: false)
        let importedStoredToken = importedToken
            ? false
            : await importStoredPersonalAccessTokenIfAvailable()

        if !importedToken && !importedStoredToken {
            isResolvingInitialContent = false
        }
    }

    private func importTokenFromGitHubCLIIfAvailable(force: Bool) async -> Bool {
        guard gitHubCLIAvailable else {
            gitHubCLIAuthStatus = .notInstalled
            if force {
                lastError = "GitHub CLI is not installed."
            }
            return false
        }

        if !force, hasToken {
            return true
        }

        gitHubCLIAuthStatus = .checking

        guard let cliToken = await GitHubCLITokenProvider.fetchToken() else {
            gitHubCLIAuthStatus = .tokenUnavailable
            if force {
                lastError = "Could not load token from `gh auth token`."
            }
            return false
        }

        return await validateAndApplyToken(cliToken, source: .githubCLI)
    }

    private func importStoredPersonalAccessTokenIfAvailable() async -> Bool {
        guard storesPersonalAccessTokenInKeychain else {
            personalAccessTokenAuthStatus = .unavailable
            return false
        }

        guard let token = storedPersonalAccessToken()
        else {
            personalAccessTokenAuthStatus = .unavailable
            return false
        }

        personalAccessTokenAuthStatus = .storedInKeychain
        return await validateAndApplyToken(token, source: .personalAccessTokenKeychain)
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
            pendingTokenCandidate = nil
            userLogin = validatedLogin
            usingGitHubCLIToken = source == .githubCLI
            usingKeychainStoredPersonalAccessToken = source == .personalAccessTokenKeychain
            tokenInput = ""
            knownLatestUpdateKeyBySubjectKey.removeAll()
            lastError = nil
            connectivityStatus = .online
            clearRateLimitState()
            pullRequestFocusCache = [:]
            suppressedTransitionNotificationKeys = []
            latestSnapshotPullRequestDashboard = .empty
            latestSnapshotIssueDashboard = .empty
            pullRequestDashboard = .empty
            issueDashboard = .empty
            pullRequestDashboardLastUpdated = nil
            issueDashboardLastUpdated = nil
            pullRequestDashboardLastError = nil
            issueDashboardLastError = nil
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

            switch source {
            case .githubCLI:
                gitHubCLIAuthStatus = .ready
            case .personalAccessTokenInput:
                if storesPersonalAccessTokenInKeychain {
                    persistStoredPersonalAccessToken(candidate)
                } else {
                    clearStoredPersonalAccessToken()
                }
            case .personalAccessTokenKeychain:
                personalAccessTokenAuthStatus = .storedInKeychain
            }

            startPollingIfNeeded()
            syncQueuedPostMergeWatchLoop()
            refreshNow()
            return true
        } catch {
            if shouldRetainTokenCandidate(after: error) {
                pendingTokenCandidate = PendingTokenCandidate(
                    token: candidate,
                    source: source
                )
                recordConnectivityFailureIfNeeded(for: error)
            } else {
                pendingTokenCandidate = nil
                updateAuthenticationStatusAfterFailure(for: error, source: source)
            }
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
            case .offline:
                return "You're offline. Octowatch will retry when the connection returns."
            case let .transport(message):
                return message
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

    private func userFacingRefreshError(for error: Error) -> String {
        if let clientError = error as? GitHubClientError {
            switch clientError {
            case .offline:
                return "You're offline. Octowatch will retry when the connection returns."
            case let .transport(message):
                return message
            default:
                return clientError.localizedDescription
            }
        }

        return error.localizedDescription
    }

    private func updateAuthenticationStatusAfterFailure(
        for error: Error,
        source: TokenSource
    ) {
        guard let clientError = error as? GitHubClientError else {
            return
        }

        switch source {
        case .githubCLI:
            switch clientError {
            case .offline, .transport:
                break
            default:
                gitHubCLIAuthStatus = .tokenRejected
            }
        case .personalAccessTokenInput:
            switch clientError {
            case .offline, .transport:
                break
            default:
                if storesPersonalAccessTokenInKeychain {
                    clearStoredPersonalAccessToken()
                }
            }
        case .personalAccessTokenKeychain:
            switch clientError {
            case .offline, .transport:
                break
            default:
                clearStoredPersonalAccessToken(rejected: true)
            }
        }
    }

    private func persistStoredPersonalAccessToken(_ token: String) {
        guard storesPersonalAccessTokenInKeychain else {
            clearStoredPersonalAccessToken()
            return
        }

        _ = keychainStore.save(
            value: token,
            account: personalAccessTokenKeychainAccount
        )
        personalAccessTokenAuthStatus = .storedInKeychain
    }

    private func clearStoredPersonalAccessToken(rejected: Bool = false) {
        _ = keychainStore.delete(account: personalAccessTokenKeychainAccount)
        for legacyKeychainStore in legacyKeychainStores {
            _ = legacyKeychainStore.delete(account: personalAccessTokenKeychainAccount)
        }
        personalAccessTokenAuthStatus = rejected ? .rejected : .unavailable
    }

    private func storedPersonalAccessToken() -> String? {
        if let token = normalizedStoredPersonalAccessToken(
            from: keychainStore,
            deleteAfterRead: false
        ) {
            return token
        }

        for legacyKeychainStore in legacyKeychainStores {
            if let token = normalizedStoredPersonalAccessToken(
                from: legacyKeychainStore,
                deleteAfterRead: true
            ) {
                _ = keychainStore.save(
                    value: token,
                    account: personalAccessTokenKeychainAccount
                )
                return token
            }
        }

        return nil
    }

    private func normalizedStoredPersonalAccessToken(
        from store: KeychainStore,
        deleteAfterRead: Bool
    ) -> String? {
        guard let rawToken = store.read(account: personalAccessTokenKeychainAccount) else {
            return nil
        }

        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            if deleteAfterRead {
                _ = store.delete(account: personalAccessTokenKeychainAccount)
            }
            return nil
        }

        if deleteAfterRead {
            _ = store.delete(account: personalAccessTokenKeychainAccount)
        }

        return token
    }

    private func shouldRetainTokenCandidate(after error: Error) -> Bool {
        guard let clientError = error as? GitHubClientError else {
            return false
        }

        switch clientError {
        case .offline, .transport:
            return true
        default:
            return false
        }
    }

    private func recordConnectivityFailureIfNeeded(for error: Error) {
        guard let clientError = error as? GitHubClientError else {
            return
        }

        switch clientError {
        case .offline:
            connectivityStatus = .offline
        case .transport:
            if connectivityStatus == .unknown {
                connectivityStatus = .offline
            }
        default:
            break
        }
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
        guard item.supportsReadState else {
            updated.isUnread = false
            return updated
        }
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
        let readableItems = items.filter(\.supportsReadState)
        let subjectKeys = Set(readableItems.map(\.subjectKey))
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
        reconcileVisibleContentFromSnapshot()
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

    private func persistSnoozedItems() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = snoozedItems.sorted { lhs, rhs in
            if lhs.snoozedUntil == rhs.snoozedUntil {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.snoozedUntil < rhs.snoozedUntil
        }

        if let data = try? encoder.encode(payload) {
            UserDefaults.standard.set(data, forKey: snoozedSubjectStoreKey)
        }
    }

    private func persistInboxSectionConfiguration() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if let data = try? encoder.encode(inboxSectionConfig.normalized) {
            UserDefaults.standard.set(data, forKey: inboxSectionConfigStoreKey)
            UserDefaults.standard.removeObject(forKey: legacyInboxSectionConfigStoreKey)
            UserDefaults.standard.removeObject(forKey: legacyInboxSectionConfigStoreKeyV1)
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

    private func persistAcknowledgedWorkflows() {
        if let data = try? JSONEncoder().encode(Array(acknowledgedWorkflows.values)) {
            UserDefaults.standard.set(data, forKey: acknowledgedWorkflowsStoreKey)
        }
    }

    private func loadAcknowledgedWorkflows() {
        guard let data = UserDefaults.standard.data(forKey: acknowledgedWorkflowsStoreKey),
              let states = try? JSONDecoder().decode([AcknowledgedWorkflowState].self, from: data)
        else { return }

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        acknowledgedWorkflows = Dictionary(
            uniqueKeysWithValues: states
                .filter { $0.acknowledgedAt > cutoff }
                .map { ($0.subjectKey, $0) }
        )
    }

    private func syncIgnoredItems() {
        ignoredItems = ignoredItemsByKey.values.sorted { lhs, rhs in
            if lhs.ignoredAt == rhs.ignoredAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.ignoredAt > rhs.ignoredAt
        }
    }

    private func syncSnoozedItems() {
        snoozedItems = snoozedItemsByKey.values.sorted { lhs, rhs in
            if lhs.snoozedUntil == rhs.snoozedUntil {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.snoozedUntil < rhs.snoozedUntil
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
        reconcileVisibleContentFromSnapshot()
    }

    private func unsnooze(_ snoozedItems: [SnoozedAttentionSubject]) {
        let snoozedKeys = Set(snoozedItems.map(\.ignoreKey))
        guard !snoozedKeys.isEmpty else {
            return
        }

        for snoozedKey in snoozedKeys {
            snoozedItemsByKey[snoozedKey] = nil
        }

        syncSnoozedItems()
        persistSnoozedItems()
        trimSnoozeUndoState(removing: snoozedKeys)
        scheduleSnoozeWakeIfNeeded()
        reconcileVisibleContentFromSnapshot()
    }

    private func reconcileVisibleContentFromSnapshot() {
        let ignoredKeys = Set(ignoredItemsByKey.keys)
        let snoozedKeys = Set(snoozedItemsByKey.keys)
        let visibleItems = AttentionItemVisibilityPolicy
            .excludingIgnoredSubjects(
                latestSnapshotAttentionItems,
                ignoredKeys: ignoredKeys
            )
        let unsnoozedItems = AttentionItemVisibilityPolicy
            .excludingSnoozedSubjects(
                visibleItems,
                snoozedKeys: snoozedKeys
            )
        let aggregatedItems = AttentionCombinedViewPolicy
            .collapsingDuplicates(in: unsnoozedItems)
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
        pullRequestDashboard = latestSnapshotPullRequestDashboard
            .filteringIgnoredSubjects(ignoredKeys)
            .filteringSnoozedSubjects(snoozedKeys)
        issueDashboard = latestSnapshotIssueDashboard
            .filteringIgnoredSubjects(ignoredKeys)
            .filteringSnoozedSubjects(snoozedKeys)
        refreshInboxSections()
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
        reconcileVisibleContentFromSnapshot()
    }

    private func presentIgnoreUndo(for ignoredItems: [IgnoredAttentionSubject]) {
        ignoreUndoDismissTask?.cancel()

        let expiry = Date().addingTimeInterval(8)
        let ignoreUndoID = ignoredItems.map(\.ignoreKey).sorted().joined(separator: "|")
        ignoreUndoState = IgnoreUndoState(subjects: ignoredItems, expiresAt: expiry)
        clearSnoozeUndoState()

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

    private func presentSnoozeUndo(for snoozedItems: [SnoozedAttentionSubject]) {
        snoozeUndoDismissTask?.cancel()

        let expiry = Date().addingTimeInterval(8)
        let snoozeUndoID = SnoozeUndoState(subjects: snoozedItems, expiresAt: expiry).id
        snoozeUndoState = SnoozeUndoState(subjects: snoozedItems, expiresAt: expiry)
        clearIgnoreUndoState()

        snoozeUndoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self?.snoozeUndoState?.id == snoozeUndoID else {
                    return
                }

                self?.clearSnoozeUndoState()
            }
        }
    }

    private func clearIgnoreUndoState() {
        ignoreUndoDismissTask?.cancel()
        ignoreUndoDismissTask = nil
        ignoreUndoState = nil
    }

    private func trimSnoozeUndoState(removing snoozedKeys: Set<String>) {
        guard let snoozeUndoState else {
            return
        }

        let remainingSubjects = snoozeUndoState.subjects.filter { subject in
            !snoozedKeys.contains(subject.ignoreKey)
        }

        if remainingSubjects.count == snoozeUndoState.subjects.count {
            return
        }

        if remainingSubjects.isEmpty {
            clearSnoozeUndoState()
        } else {
            self.snoozeUndoState = SnoozeUndoState(
                subjects: remainingSubjects,
                expiresAt: snoozeUndoState.expiresAt
            )
        }
    }

    private func clearSnoozeUndoState() {
        snoozeUndoDismissTask?.cancel()
        snoozeUndoDismissTask = nil
        snoozeUndoState = nil
    }

    private func scheduleSnoozeWakeIfNeeded() {
        snoozeWakeTask?.cancel()

        guard let nextWake = snoozedItemsByKey.values.map(\.snoozedUntil).min() else {
            snoozeWakeTask = nil
            return
        }

        let delay = max(nextWake.timeIntervalSinceNow, 0.1)
        snoozeWakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.trimExpiredSnoozedItems(relativeTo: Date())
            }
        }
    }

    private func trimExpiredSnoozedItems(relativeTo referenceDate: Date) {
        let expiredKeys = snoozedItemsByKey.values
            .filter { $0.snoozedUntil <= referenceDate }
            .map(\.ignoreKey)
        guard !expiredKeys.isEmpty else {
            scheduleSnoozeWakeIfNeeded()
            return
        }

        for expiredKey in expiredKeys {
            snoozedItemsByKey[expiredKey] = nil
        }

        syncSnoozedItems()
        persistSnoozedItems()
        trimSnoozeUndoState(removing: Set(expiredKeys))
        scheduleSnoozeWakeIfNeeded()
        reconcileVisibleContentFromSnapshot()
    }

    private func refreshInboxSections() {
        inboxSections = InboxSectionPolicy.matchingItemsBySection(
            in: attentionItems,
            configuration: inboxSectionConfig,
            acknowledgedWorkflows: acknowledgedWorkflows
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

    private static func loadSnoozedItems(
        from defaults: UserDefaults,
        key: String
    ) -> [String: SnoozedAttentionSubject] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let items = try? decoder.decode([SnoozedAttentionSubject].self, from: data) else {
            return [:]
        }

        let now = Date()
        let activeItems = items.filter { $0.snoozedUntil > now }
        return Dictionary(uniqueKeysWithValues: activeItems.map { ($0.ignoreKey, $0) })
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
        let summary = preferredAttentionSummary(for: item)
        return IgnoredAttentionSubject(
            ignoreKey: summary.ignoreKey,
            title: summary.title,
            subtitle: summary.subtitle,
            url: summary.url,
            ignoredAt: Date()
        )
    }

    private func preferredSnoozedSummary(
        for item: AttentionItem,
        snoozedAt: Date,
        snoozedUntil: Date
    ) -> SnoozedAttentionSubject {
        let summary = preferredAttentionSummary(for: item)
        return SnoozedAttentionSubject(
            ignoreKey: summary.ignoreKey,
            title: summary.title,
            subtitle: summary.subtitle,
            url: summary.url,
            snoozedAt: snoozedAt,
            snoozedUntil: snoozedUntil
        )
    }

    private func preferredAttentionSummary(
        for item: AttentionItem
    ) -> (ignoreKey: String, title: String, subtitle: String, url: URL) {
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

        return (
            ignoreKey: representative.ignoreKey,
            title: representative.title,
            subtitle: representative.subtitle,
            url: representative.url
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
                .securityAlert,
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

    private static func loadInboxSectionConfiguration(
        from defaults: UserDefaults,
        key: String,
        legacyKey: String,
        legacyKeyV1: String
    ) -> InboxSectionConfiguration {
        if let data = defaults.data(forKey: key),
            let configuration = try? JSONDecoder().decode(InboxSectionConfiguration.self, from: data) {
            return configuration.normalized
        }

        if let data = defaults.data(forKey: legacyKey),
            let configuration = try? JSONDecoder().decode(InboxSectionConfiguration.self, from: data) {
            return configuration.migratingV2ToV3()
        }

        if let data = defaults.data(forKey: legacyKeyV1),
            let legacyConfiguration = try? JSONDecoder().decode(
                LegacyInboxSectionConfiguration.self,
                from: data
            ) {
            return InboxSectionConfiguration.migrated(from: legacyConfiguration).migratingV2ToV3()
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
        key: String,
        defaultValue: Bool = false
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func hasExistingPersistentState() -> Bool {
        let defaults = UserDefaults.standard
        let domainNames = [
            Bundle.main.bundleIdentifier ?? "app.octowatch.macos",
            "app.octowatch.macos",
            "dev.octowatch.app",
            "dev.octobar.app"
        ]

        return domainNames.contains { domainName in
            defaults.persistentDomain(forName: domainName) != nil
        }
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
        token = fixture.token
        tokenInput = ""
        userLogin = fixture.login
        latestSnapshotAttentionItems = fixture.attentionItems
        latestSnapshotPullRequestDashboard = .empty
        latestSnapshotIssueDashboard = .empty
        attentionItems = fixture.attentionItems
        pullRequestDashboard = .empty
        issueDashboard = .empty
        isPullRequestDashboardRefreshing = false
        isIssueDashboardRefreshing = false
        pullRequestDashboardLastUpdated = nil
        issueDashboardLastUpdated = nil
        pullRequestDashboardLastError = nil
        issueDashboardLastError = nil
        inboxSectionConfig = .default
        inboxSections = InboxSectionPolicy.matchingItemsBySection(
            in: fixture.attentionItems,
            configuration: inboxSectionConfig
        )
        lastUpdated = fixture.lastUpdated
        lastError = fixture.lastError
        isResolvingInitialContent = false
        gitHubCLIAvailable = fixture.gitHubCLIAvailable
        gitHubCLIAuthStatus = fixture.gitHubCLIAuthStatus
        personalAccessTokenAuthStatus = fixture.personalAccessTokenAuthStatus
        storesPersonalAccessTokenInKeychain = fixture.storesPersonalAccessTokenInKeychain
        usingGitHubCLIToken = fixture.usingGitHubCLIToken
        usingKeychainStoredPersonalAccessToken = fixture.usingKeychainStoredPersonalAccessToken
        hasCompletedInitialSetup = fixture.hasCompletedInitialSetup
        settingsNavigationTarget = nil
        isValidatingToken = false
        connectivityStatus = fixture.connectivityStatus
        clearRateLimitState()
        knownLatestUpdateKeyBySubjectKey = Dictionary(
            uniqueKeysWithValues: fixture.attentionItems.map { ($0.subjectKey, $0.updateKey) }
        )
        ignoredItemsByKey = [:]
        ignoredItems = []
        snoozedItemsByKey = [:]
        snoozedItems = []
        readStateBySubjectKey = [:]
        updateHistoryBySubjectKey = [:]
        ignoreUndoState = nil
        snoozeUndoState = nil
        autoMarkReadSetting = fixture.autoMarkReadSetting
        notifyOnSelfTriggeredUpdates = false
        showsMenuBarIcon = true
        showsDebugRateLimitDetails = false
        notificationScanState = .default
        teamMembershipCache = .default
        pendingTokenCandidate = fixture.hasPendingGitHubCLIToken
            ? PendingTokenCandidate(token: "ui-test-token", source: .githubCLI)
            : nil
        pullRequestFocusCache = Dictionary(
            uniqueKeysWithValues: fixture.pullRequestFocusesBySubjectKey.map { subjectKey, focus in
                (
                    subjectKey,
                    PullRequestFocusCacheEntry(
                        focus: focus,
                        subjectRefresh: AttentionSubjectRefresh(
                            subjectKey: subjectKey,
                            labels: [],
                            mergedAt: nil,
                            supplementalItems: []
                        ),
                        sourceTimestamp: fixture.attentionItems.first(where: { $0.subjectKey == subjectKey })?.timestamp ?? fixture.lastUpdated,
                        loadedAt: Date()
                    )
                )
            }
        )
        suppressedTransitionNotificationKeys = []
        snoozeWakeTask?.cancel()
        snoozeWakeTask = nil
    }
}

private struct LaunchFixture {
    let token: String?
    let login: String?
    let attentionItems: [AttentionItem]
    let pullRequestFocusesBySubjectKey: [String: PullRequestFocus]
    let autoMarkReadSetting: AutoMarkReadSetting
    let lastUpdated: Date
    let lastError: String?
    let connectivityStatus: AppConnectivityStatus
    let gitHubCLIAvailable: Bool
    let gitHubCLIAuthStatus: GitHubCLIAuthStatus
    let personalAccessTokenAuthStatus: PersonalAccessTokenAuthStatus
    let storesPersonalAccessTokenInKeychain: Bool
    let usingGitHubCLIToken: Bool
    let usingKeychainStoredPersonalAccessToken: Bool
    let hasCompletedInitialSetup: Bool
    let hasPendingGitHubCLIToken: Bool

    static func load(from environment: [String: String]) -> LaunchFixture? {
        let fixtureName = environment["OCTOWATCH_LAUNCH_FIXTURE"] ??
            environment["OCTOWATCH_UI_TEST_FIXTURE"]

        switch fixtureName {
        case "auto-mark-read":
            return autoMarkReadFixture
        case "auth-wizard-gh-found":
            return authWizardFixture(
                gitHubCLIAvailable: true,
                gitHubCLIAuthStatus: .tokenUnavailable
            )
        case "auth-wizard-gh-missing":
            return authWizardFixture(
                gitHubCLIAvailable: false,
                gitHubCLIAuthStatus: .notInstalled
            )
        case "draft-authored-pull-request":
            return draftAuthoredPullRequestFixture
        case "first-run-gh-ready":
            return firstRunGitHubCLIFixture
        case "notification-security-alert":
            return notificationSecurityAlertFixture(isUnread: true)
        case "notification-security-alert-read":
            return notificationSecurityAlertFixture(isUnread: false)
        case "offline-startup":
            return offlineStartupFixture
        case "readme-demo":
            return readmeDemoFixture
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
            token: "ui-test-token",
            login: "octowatch-ui-test",
            attentionItems: [primaryItem, secondaryItem],
            pullRequestFocusesBySubjectKey: [:],
            autoMarkReadSetting: .oneSecond,
            lastUpdated: now,
            lastError: nil,
            connectivityStatus: .online,
            gitHubCLIAvailable: false,
            gitHubCLIAuthStatus: .notInstalled,
            personalAccessTokenAuthStatus: .unavailable,
            storesPersonalAccessTokenInKeychain: true,
            usingGitHubCLIToken: false,
            usingKeychainStoredPersonalAccessToken: false,
            hasCompletedInitialSetup: true,
            hasPendingGitHubCLIToken: false
        )
    }

    private static var draftAuthoredPullRequestFixture: LaunchFixture {
        let now = Date()
        let repository = "example/octowatch"
        let reference = PullRequestReference(
            owner: "example",
            name: "octowatch",
            number: 42
        )
        let author = AttentionActor(
            login: "octowatch-ui-test",
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/9919?v=4")
        )
        let subjectKey = reference.pullRequestURL.absoluteString
        let reviewMergeAction = PullRequestReviewMergeAction.makeAction(
            sourceType: .authoredPullRequest,
            mode: .authored,
            author: author,
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: true,
            reviewDecision: nil,
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: .empty,
            openThreadCount: 0
        )
        let readyForReviewAction = PullRequestReadyForReviewAction.makeAction(
            mode: .authored,
            resolution: .open,
            isDraft: true
        )
        let item = AttentionItem(
            id: "fixture-draft-pr",
            subjectKey: subjectKey,
            type: .authoredPullRequest,
            title: "Draft UI fixture pull request",
            subtitle: "\(repository) · Draft · Created by you",
            repository: repository,
            timestamp: now.addingTimeInterval(-3600),
            url: reference.pullRequestURL,
            subjectResolution: .open,
            detail: AttentionDetail(
                why: AttentionWhy(
                    summary: "You authored this draft pull request.",
                    detail: "This pull request is still a draft."
                ),
                evidence: [],
                actions: []
            ),
            isDraft: true
        )
        let focus = PullRequestFocus(
            reference: reference,
            baseBranch: "main",
            sourceType: .authoredPullRequest,
            mode: .authored,
            resolution: .open,
            mergedAt: nil,
            author: author,
            labels: [],
            headerFacts: [],
            contextBadges: [],
            descriptionHTML: nil,
            statusSummary: PullRequestStatusSummary.build(
                mode: .authored,
                resolution: .open,
                checkSummary: .empty,
                openThreadCount: 0,
                reviewMergeAction: reviewMergeAction
            ),
            postMergeWorkflowPreview: nil,
            sections: [],
            timeline: [],
            actions: AttentionAction.pullRequestActions(
                reference: reference,
                mode: .authored,
                checkSummary: .empty,
                hasNewCommits: false,
                hasPrimaryMutationAction: true
            ),
            readyForReviewAction: readyForReviewAction,
            reviewMergeAction: reviewMergeAction,
            emptyStateTitle: "No additional pull request activity yet",
            emptyStateDetail: "Mark this draft ready for review when it is ready."
        )

        return LaunchFixture(
            token: "ui-test-token",
            login: "octowatch-ui-test",
            attentionItems: [item],
            pullRequestFocusesBySubjectKey: [subjectKey: focus],
            autoMarkReadSetting: .never,
            lastUpdated: now,
            lastError: nil,
            connectivityStatus: .online,
            gitHubCLIAvailable: false,
            gitHubCLIAuthStatus: .notInstalled,
            personalAccessTokenAuthStatus: .unavailable,
            storesPersonalAccessTokenInKeychain: true,
            usingGitHubCLIToken: false,
            usingKeychainStoredPersonalAccessToken: false,
            hasCompletedInitialSetup: true,
            hasPendingGitHubCLIToken: false
        )
    }

    private static var firstRunGitHubCLIFixture: LaunchFixture {
        let now = Date()

        return LaunchFixture(
            token: "ui-test-token",
            login: "octowatch-ui-test",
            attentionItems: [],
            pullRequestFocusesBySubjectKey: [:],
            autoMarkReadSetting: .threeSeconds,
            lastUpdated: now,
            lastError: nil,
            connectivityStatus: .online,
            gitHubCLIAvailable: true,
            gitHubCLIAuthStatus: .ready,
            personalAccessTokenAuthStatus: .unavailable,
            storesPersonalAccessTokenInKeychain: true,
            usingGitHubCLIToken: true,
            usingKeychainStoredPersonalAccessToken: false,
            hasCompletedInitialSetup: false,
            hasPendingGitHubCLIToken: false
        )
    }

    private static var readmeDemoFixture: LaunchFixture {
        let now = Date()
        let repository = "example/octowatch"
        let reference = PullRequestReference(
            owner: "example",
            name: "octowatch",
            number: 42
        )
        let subjectKey = reference.pullRequestURL.absoluteString
        let author = AttentionActor(
            login: "product-maintainer",
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/9919?v=4")
        )
        let reviewer = AttentionActor(
            login: "octowatch-user",
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1296269?v=4")
        )
        let automation = AttentionActor(
            login: "release-assistant[bot]",
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/49699333?v=4"),
            isBot: true
        )
        let checkSummary = PullRequestCheckSummary(
            passedCount: 18,
            skippedCount: 2,
            failedCount: 1,
            pendingCount: 0
        )

        let reviewRequestedItem = AttentionItem(
            id: "fixture-readme-pr",
            subjectKey: subjectKey,
            stream: .pullRequests,
            type: .reviewRequested,
            secondaryIndicatorType: .pullRequestFailedChecks,
            focusType: .reviewRequested,
            title: "Polish the first-run setup experience",
            subtitle: "\(repository) · Review requested",
            repository: repository,
            labels: [
                GitHubLabel(name: "macOS", colorHex: "1f6feb", description: "Native app work"),
                GitHubLabel(name: "SwiftUI", colorHex: "bf3989", description: "SwiftUI surface"),
                GitHubLabel(name: "onboarding", colorHex: "0e8a16", description: "First-run flow")
            ],
            timestamp: now.addingTimeInterval(-240),
            url: reference.pullRequestURL,
            actor: reviewer,
            detail: AttentionDetail(
                why: AttentionWhy(
                    summary: "A pull request is waiting for your review.",
                    detail: "Checks regressed after the latest onboarding polish."
                ),
                evidence: [
                    AttentionEvidence(
                        id: "repository",
                        title: "Repository",
                        detail: repository,
                        iconName: "shippingbox",
                        url: URL(string: "https://github.com/\(repository)")!
                    )
                ],
                updates: [
                    AttentionUpdate(
                        id: "fixture-readme-update-review-requested",
                        type: .reviewRequested,
                        title: "Review requested",
                        detail: "The latest onboarding pass needs a fresh review.",
                        timestamp: now.addingTimeInterval(-240),
                        actor: reviewer,
                        url: reference.pullRequestURL
                    ),
                    AttentionUpdate(
                        id: "fixture-readme-update-failed-check",
                        type: .pullRequestFailedChecks,
                        title: "Checks failed",
                        detail: "Screenshot capture",
                        timestamp: now.addingTimeInterval(-180),
                        actor: automation,
                        url: reference.checksURL
                    )
                ],
                actions: AttentionAction.pullRequestActions(
                    reference: reference,
                    mode: .participating,
                    checkSummary: checkSummary,
                    hasNewCommits: true,
                    hasPrimaryMutationAction: false
                )
            ),
            currentUpdateTypes: [.pullRequestFailedChecks],
            currentRelationshipTypes: [.reviewRequested],
            isUnread: true
        )

        let reviewFocus = PullRequestFocus(
            reference: reference,
            baseBranch: "main",
            sourceType: .reviewRequested,
            mode: .participating,
            resolution: .open,
            mergedAt: nil,
            author: author,
            labels: reviewRequestedItem.labels,
            headerFacts: PullRequestHeaderFact.build(
                sourceType: .reviewRequested,
                resolution: .open,
                sourceActor: reviewer,
                author: author,
                assigner: nil,
                latestApprover: nil,
                approvalCount: 0,
                mergedBy: nil
            ),
            contextBadges: [
                PullRequestContextBadge(
                    id: "checks-failed",
                    title: "Checks failed",
                    iconName: "xmark.octagon.fill",
                    accent: .failure
                )
            ],
            descriptionHTML: """
                <p>Refresh the first-run flow so the app explains GitHub CLI,
                personal access tokens, and offline recovery without dropping
                people into a dead end.</p>
                <ul>
                  <li>Keep the setup path native to macOS.</li>
                  <li>Explain when manual PAT setup is required.</li>
                  <li>Leave the main window mounted behind the setup sheet.</li>
                </ul>
                """,
            statusSummary: PullRequestStatusSummary.build(
                mode: .participating,
                checkSummary: checkSummary,
                openThreadCount: 1,
                reviewMergeAction: nil,
                commitsSinceReview: [
                    PullRequestFocusEntry(
                        id: "fixture-readme-commit-summary",
                        title: "Tighten onboarding copy and recovery flow",
                        detail: "9f4d1a2",
                        metadata: automation.login,
                        timestamp: now.addingTimeInterval(-600),
                        iconName: "arrow.trianglehead.branch",
                        accent: .change,
                        url: reference.commitsURL
                    )
                ]
            ),
            postMergeWorkflowPreview: nil,
            sections: [
                PullRequestFocusSection(
                    id: "open-threads",
                    title: "Your Open Conversations",
                    items: [
                        PullRequestFocusEntry(
                            id: "fixture-readme-thread",
                            title: "Sources/Octobar/AttentionWindowView.swift:214",
                            detail: "Explain why GitHub CLI is preferred before the PAT path.",
                            metadata: reviewer.login,
                            timestamp: now.addingTimeInterval(-540),
                            iconName: "bubble.left.and.text.bubble.right",
                            accent: .warning,
                            url: reference.pullRequestURL
                        )
                    ]
                ),
                PullRequestFocusSection(
                    id: "changes-since-review",
                    title: "Changes Since Your Review",
                    items: [
                        PullRequestFocusEntry(
                            id: "fixture-readme-commit",
                            title: "Add a dedicated recovery state for offline launch",
                            detail: "9f4d1a2",
                            metadata: automation.login,
                            timestamp: now.addingTimeInterval(-420),
                            iconName: "arrow.trianglehead.branch",
                            accent: .change,
                            url: reference.commitsURL
                        )
                    ]
                ),
                PullRequestFocusSection(
                    id: "failed-checks",
                    title: "Failing Checks",
                    items: [
                        PullRequestFocusEntry(
                            id: "fixture-readme-check",
                            title: "Screenshot capture",
                            detail: "failure",
                            metadata: "github-actions",
                            timestamp: now.addingTimeInterval(-210),
                            iconName: "xmark.octagon",
                            accent: .failure,
                            url: reference.checksURL
                        )
                    ]
                )
            ],
            timeline: [
                PullRequestTimelineEntry(
                    id: "fixture-readme-timeline-comment",
                    kind: .comment,
                    author: reviewer,
                    bodyHTML: "<p>The sheet is good now. The copy still needs to explain what happens when the Mac is offline.</p>",
                    timestamp: now.addingTimeInterval(-1_200),
                    url: reference.pullRequestURL
                ),
                PullRequestTimelineEntry(
                    id: "fixture-readme-timeline-review",
                    kind: .review(state: "COMMENTED"),
                    author: reviewer,
                    bodyHTML: "<p>Please make the first-run path explicit when GitHub CLI is already configured.</p>",
                    timestamp: now.addingTimeInterval(-900),
                    url: reference.pullRequestURL
                )
            ],
            actions: AttentionAction.pullRequestActions(
                reference: reference,
                mode: .participating,
                checkSummary: checkSummary,
                hasNewCommits: true,
                hasPrimaryMutationAction: false
            ),
            readyForReviewAction: nil,
            reviewMergeAction: nil,
            emptyStateTitle: "No additional pull request signals",
            emptyStateDetail: "The latest review request already tells the story here."
        )

        let workflowItem = AttentionItem(
            id: "fixture-readme-workflow",
            subjectKey: "https://github.com/\(repository)/actions/runs/9001",
            type: .workflowApprovalRequired,
            title: "Approve production deployment",
            subtitle: "\(repository) · Workflow waiting for approval",
            repository: repository,
            timestamp: now.addingTimeInterval(-480),
            url: URL(string: "https://github.com/\(repository)/actions/runs/9001")!,
            actor: automation,
            isUnread: true
        )

        let securityItem = AttentionItem(
            id: "fixture-readme-security",
            subjectKey: "https://github.com/example/security-lab/security/dependabot/7",
            stream: .notifications,
            type: .securityAlert,
            title: "Security alert in dependency snapshot",
            subtitle: "example/security-lab · Security alert",
            repository: "example/security-lab",
            timestamp: now.addingTimeInterval(-720),
            url: URL(string: "https://github.com/example/security-lab/security/dependabot/7")!,
            isUnread: false
        )

        let draftItem = AttentionItem(
            id: "fixture-readme-draft",
            subjectKey: "https://github.com/example/octowatch/pull/38",
            stream: .pullRequests,
            type: .authoredPullRequest,
            title: "Draft: add a lighter menu bar quick-view",
            subtitle: "\(repository) · Draft · Created by you",
            repository: repository,
            timestamp: now.addingTimeInterval(-1_080),
            url: URL(string: "https://github.com/\(repository)/pull/38")!,
            actor: author,
            isDraft: true,
            isUnread: false
        )

        return LaunchFixture(
            token: "ui-test-token",
            login: "octowatch-user",
            attentionItems: [
                reviewRequestedItem,
                workflowItem,
                securityItem,
                draftItem
            ],
            pullRequestFocusesBySubjectKey: [subjectKey: reviewFocus],
            autoMarkReadSetting: .threeSeconds,
            lastUpdated: now.addingTimeInterval(-18),
            lastError: nil,
            connectivityStatus: .online,
            gitHubCLIAvailable: true,
            gitHubCLIAuthStatus: .ready,
            personalAccessTokenAuthStatus: .unavailable,
            storesPersonalAccessTokenInKeychain: true,
            usingGitHubCLIToken: true,
            usingKeychainStoredPersonalAccessToken: false,
            hasCompletedInitialSetup: true,
            hasPendingGitHubCLIToken: false
        )
    }

    private static func notificationSecurityAlertFixture(isUnread: Bool) -> LaunchFixture {
        let now = Date()
        let repository = "example/security-lab"
        let alertURL = URL(string: "https://github.com/\(repository)/security/dependabot/42")!

        let item = AttentionItem(
            id: isUnread ? "fixture-security-alert" : "fixture-security-alert-read",
            subjectKey: alertURL.absoluteString,
            stream: .notifications,
            type: .securityAlert,
            title: "Your repository has dependencies with security vulnerabilities",
            subtitle: "\(repository) · Security alert",
            repository: repository,
            timestamp: now.addingTimeInterval(-10_800),
            url: alertURL,
            detail: AttentionDetail(
                why: AttentionWhy(
                    summary: "GitHub detected a security alert for this repository.",
                    detail: "GitHub raised a repository security alert."
                ),
                evidence: [
                    AttentionEvidence(
                        id: "repository",
                        title: "Repository",
                        detail: repository,
                        iconName: "shippingbox",
                        url: URL(string: "https://github.com/\(repository)")!
                    ),
                    AttentionEvidence(
                        id: "target",
                        title: "Why this surfaced",
                        detail: "GitHub raised a repository security alert.",
                        iconName: "person"
                    ),
                    AttentionEvidence(
                        id: "security-alert",
                        title: "Security alert",
                        detail: "Dependabot alert",
                        iconName: "exclamationmark.shield",
                        url: alertURL
                    )
                ],
                actions: [
                    AttentionAction(
                        id: "open-subject",
                        title: "Open Security Alert",
                        iconName: "arrow.up.right.square",
                        url: alertURL,
                        isPrimary: true
                    )
                ],
                acknowledgement: "Use the toolbar to mark this read or ignore it."
            ),
            isUnread: isUnread
        )

        return LaunchFixture(
            token: "ui-test-token",
            login: "octowatch-ui-test",
            attentionItems: [item],
            pullRequestFocusesBySubjectKey: [:],
            autoMarkReadSetting: .threeSeconds,
            lastUpdated: now,
            lastError: nil,
            connectivityStatus: .online,
            gitHubCLIAvailable: false,
            gitHubCLIAuthStatus: .notInstalled,
            personalAccessTokenAuthStatus: .unavailable,
            storesPersonalAccessTokenInKeychain: true,
            usingGitHubCLIToken: false,
            usingKeychainStoredPersonalAccessToken: false,
            hasCompletedInitialSetup: true,
            hasPendingGitHubCLIToken: false
        )
    }

    private static func authWizardFixture(
        gitHubCLIAvailable: Bool,
        gitHubCLIAuthStatus: GitHubCLIAuthStatus
    ) -> LaunchFixture {
        LaunchFixture(
            token: nil,
            login: nil,
            attentionItems: [],
            pullRequestFocusesBySubjectKey: [:],
            autoMarkReadSetting: .threeSeconds,
            lastUpdated: Date(),
            lastError: nil,
            connectivityStatus: .online,
            gitHubCLIAvailable: gitHubCLIAvailable,
            gitHubCLIAuthStatus: gitHubCLIAuthStatus,
            personalAccessTokenAuthStatus: .unavailable,
            storesPersonalAccessTokenInKeychain: true,
            usingGitHubCLIToken: false,
            usingKeychainStoredPersonalAccessToken: false,
            hasCompletedInitialSetup: true,
            hasPendingGitHubCLIToken: false
        )
    }

    private static var offlineStartupFixture: LaunchFixture {
        LaunchFixture(
            token: nil,
            login: nil,
            attentionItems: [],
            pullRequestFocusesBySubjectKey: [:],
            autoMarkReadSetting: .threeSeconds,
            lastUpdated: Date(),
            lastError: "You're offline. Octowatch will retry when the connection returns.",
            connectivityStatus: .offline,
            gitHubCLIAvailable: true,
            gitHubCLIAuthStatus: .checking,
            personalAccessTokenAuthStatus: .unavailable,
            storesPersonalAccessTokenInKeychain: true,
            usingGitHubCLIToken: false,
            usingKeychainStoredPersonalAccessToken: false,
            hasCompletedInitialSetup: true,
            hasPendingGitHubCLIToken: true
        )
    }
}

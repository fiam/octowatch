import AppKit
import SwiftUI

struct AttentionWindowView: View {
    private enum InboxMode: String, CaseIterable, Identifiable {
        case inbox
        case browse

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inbox:
                return "Inbox"
            case .browse:
                return "Browse"
            }
        }
    }

    private enum BrowseScope: String, CaseIterable, Identifiable {
        case pullRequests
        case issues

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pullRequests:
                return "My PRs"
            case .issues:
                return "My Issues"
            }
        }

        var itemNoun: String {
            switch self {
            case .pullRequests:
                return "pull request"
            case .issues:
                return "issue"
            }
        }
    }

    private struct SidebarSectionDescriptor: Identifiable {
        let id: String
        let title: String
        let items: [AttentionItem]
    }

    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    @State private var selectedItemIDs = Set<AttentionItem.ID>()
    @State private var inboxMode: InboxMode = .inbox
    @State private var browseScope: BrowseScope = .pullRequests
    @State private var pullRequestDashboardFilter: PullRequestDashboardFilter = .created
    @State private var issueDashboardFilter: IssueDashboardFilter = .assigned
    @State private var showsUnreadOnly = false
    @State private var autoMarkReadTask: Task<Void, Never>?
    @State private var autoSelectionTask: Task<Void, Never>?
    @State private var pullRequestFocusState: PullRequestFocusLoadState = .idle
    @State private var reviewMergeState: PullRequestReviewMergeState = .idle
    @State private var workflowApprovalSheetRequest: WorkflowApprovalSheetRequest?

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            windowContent(relativeTo: context.date)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 620)
        .onAppear {
            syncSelection()
            updateWatchedPullRequestSelection()
        }
        .onDisappear {
            cancelAutoMarkReadTask()
            cancelAutoSelectionTask()
            model.setWatchedPullRequest(nil)
        }
        .onChange(of: model.attentionItems) { _, _ in
            syncSelection()
        }
        .onChange(of: model.pullRequestDashboard) { _, _ in
            syncSelection()
        }
        .onChange(of: model.issueDashboard) { _, _ in
            syncSelection()
        }
        .onChange(of: showsUnreadOnly) { _, _ in
            syncSelection()
        }
        .onChange(of: inboxMode) { _, _ in
            syncSelection()
            Task {
                await loadDashboardIfNeeded()
            }
        }
        .onChange(of: browseScope) { _, _ in
            syncSelection()
            Task {
                await loadDashboardIfNeeded()
            }
        }
        .onChange(of: pullRequestDashboardFilter) { _, _ in
            syncSelection()
        }
        .onChange(of: issueDashboardFilter) { _, _ in
            syncSelection()
        }
        .onChange(of: model.autoMarkReadSetting) { _, _ in
            if autoMarkReadTask != nil {
                armAutoMarkReadForCurrentSelection()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.ignoreUndoState?.id)
        .task(id: dashboardLoadTaskID) {
            await loadDashboardIfNeeded()
        }
        .task(id: pullRequestFocusTaskID) {
            await loadPullRequestFocusForSelection()
        }
        .sheet(item: $workflowApprovalSheetRequest) { request in
            WorkflowPendingDeploymentReviewSheet(
                model: model,
                request: request,
                onOpenGitHub: { url in
                    openURL(url)
                }
            )
        }
        .toolbar {
            if !selectionActionItems.isEmpty, model.hasToken {
                ToolbarItemGroup {
                    Button {
                        openSelection(selectionActionItems)
                    } label: {
                        Label("Open", systemImage: "safari")
                    }
                    .appInteractiveHover()
                    .help(selectionActionItems.count == 1 ? "Open on GitHub" : "Open selected items on GitHub")

                    if showsReadActions {
                        Button {
                            performPrimaryReadAction(for: selectionActionItems)
                        } label: {
                            Label(
                                primaryReadActionTitle,
                                systemImage: primaryReadActionSymbol
                            )
                        }
                        .appInteractiveHover()
                        .keyboardShortcut("u", modifiers: [.command, .shift])
                        .accessibilityIdentifier("item-toggle-read-state")
                        .accessibilityLabel(primaryReadActionTitle)
                        .help(primaryReadActionTitle)
                    }

                    Button {
                        ignoreSelection(selectionActionItems)
                    } label: {
                        Label("Ignore", systemImage: "eye.slash")
                    }
                    .appInteractiveHover()
                    .help(selectionActionItems.count == 1 ? selectionActionItems[0].ignoreActionTitle : "Ignore selected items")
                }
            }

            if selectedItem != nil, model.hasToken {
                ToolbarItem {
                    Button {
                        guard let item = selectedItem else {
                            return
                        }

                        Task {
                            await refreshSelection(item)
                        }
                    } label: {
                        Label("Refresh Item", systemImage: "arrow.clockwise")
                    }
                    .disabled(isScopeRefreshing)
                    .appInteractiveHover()
                    .keyboardShortcut("r", modifiers: [.command])
                    .help("Refresh selected item")
                }
            }

            ToolbarItem {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .appInteractiveHover()
                .help("Settings")
            }
        }
    }

    @ViewBuilder
    private func windowContent(relativeTo referenceDate: Date) -> some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationSplitView {
                sidebar(relativeTo: referenceDate)
            } detail: {
                detailPane(relativeTo: referenceDate)
            }

            if let ignoreUndoState = model.ignoreUndoState {
                IgnoreUndoBanner(
                    state: ignoreUndoState,
                    onUndo: model.undoRecentIgnore,
                    onDismiss: model.dismissIgnoreUndo
                )
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var showsLoadingState: Bool {
        if model.isResolvingInitialContent && !model.hasToken {
            return true
        }

        switch inboxMode {
        case .inbox:
            return model.hasToken &&
                model.lastUpdated == nil &&
                model.isRefreshing &&
                displayedItems.isEmpty &&
                currentError == nil
        case .browse:
            switch browseScope {
            case .pullRequests:
                return model.hasToken &&
                    model.pullRequestDashboardLastUpdated == nil &&
                    model.isPullRequestDashboardRefreshing &&
                    displayedItems.isEmpty &&
                    currentError == nil
            case .issues:
                return model.hasToken &&
                    model.issueDashboardLastUpdated == nil &&
                    model.isIssueDashboardRefreshing &&
                    displayedItems.isEmpty &&
                    currentError == nil
            }
        }
    }

    private var scopedItems: [AttentionItem] {
        switch inboxMode {
        case .inbox:
            return model.combinedAttentionItems
        case .browse:
            switch browseScope {
            case .pullRequests:
                return model.pullRequestDashboardItems(for: pullRequestDashboardFilter)
            case .issues:
                return model.issueDashboardItems(for: issueDashboardFilter)
            }
        }
    }

    private var visibleItems: [AttentionItem] {
        guard inboxMode == .inbox, showsUnreadOnly else {
            return scopedItems
        }

        return scopedItems.filter(\.isUnread)
    }

    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text(loadingTitle)
                .font(.title3.weight(.semibold))

            Text(loadingSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var loadingTitle: String {
        switch inboxMode {
        case .inbox:
            return "Refreshing inbox…"
        case .browse:
            switch browseScope {
            case .pullRequests:
                return "Refreshing pull requests…"
            case .issues:
                return "Refreshing issues…"
            }
        }
    }

    private var loadingSubtitle: String {
        switch inboxMode {
        case .inbox:
            return "Fetching the latest GitHub activity."
        case .browse:
            switch browseScope {
            case .pullRequests:
                return "Loading your pull request dashboard."
            case .issues:
                return "Loading your issue dashboard."
            }
        }
    }

    private var displayedItems: [AttentionItem] {
        displayedSections.flatMap(\.items)
    }

    private var yourTurnSubjectKeys: Set<String> {
        Set(model.yourTurnItems.map(\.subjectKey))
    }

    private var scopedYourTurnItems: [AttentionItem] {
        guard inboxMode == .inbox else {
            return []
        }

        return model.yourTurnItems
    }

    private var yourTurnItemsInCurrentStream: [AttentionItem] {
        visibleItems.filter { yourTurnSubjectKeys.contains($0.subjectKey) }
    }

    private var displayedYourTurnItems: [AttentionItem] {
        yourTurnItemsInCurrentStream
    }

    private var displayedOtherItems: [AttentionItem] {
        guard inboxMode == .inbox else {
            return visibleItems
        }

        return visibleItems.filter { !yourTurnSubjectKeys.contains($0.subjectKey) }
    }

    private var displayedSections: [SidebarSectionDescriptor] {
        var sections = [SidebarSectionDescriptor]()

        if !displayedYourTurnItems.isEmpty {
            sections.append(
                SidebarSectionDescriptor(
                    id: "your-turn",
                    title: "Your Turn",
                    items: displayedYourTurnItems
                )
            )
        }

        if !displayedOtherItems.isEmpty {
            switch inboxMode {
            case .inbox:
                sections.append(
                    SidebarSectionDescriptor(
                        id: "recent",
                        title: "Recent",
                        items: displayedOtherItems
                    )
                )
            case .browse:
                sections.append(
                    SidebarSectionDescriptor(
                        id: browseScope.rawValue,
                        title: currentSectionTitle,
                        items: displayedOtherItems
                    )
                )
            }
        }

        return sections
    }

    private var selectionActionItems: [AttentionItem] {
        displayedItems.filter { selectedItemIDs.contains($0.id) }
    }

    private var selectedItem: AttentionItem? {
        guard selectionActionItems.count == 1 else {
            return nil
        }

        return selectionActionItems.first
    }

    private var showsReadActions: Bool {
        selectionActionItems.contains(where: \.supportsReadState)
    }

    private var primaryReadActionTitle: String {
        selectionActionItems.contains(where: \.isUnread) ? "Mark Read" : "Mark Unread"
    }

    private var primaryReadActionSymbol: String {
        selectionActionItems.contains(where: \.isUnread) ? "circle" : "circle.fill"
    }

    private var pullRequestFocusTaskID: String? {
        guard let item = selectedItem, item.pullRequestReference != nil else {
            return nil
        }

        return "\(item.ignoreKey)#\(item.timestamp.timeIntervalSince1970)#\(model.lastUpdated?.timeIntervalSince1970 ?? 0)"
            + "#\(model.pullRequestWatchRevision)"
    }

    private var currentSectionTitle: String {
        switch inboxMode {
        case .inbox:
            return "Inbox"
        case .browse:
            switch browseScope {
            case .pullRequests:
                return "\(pullRequestDashboardFilter.title) Pull Requests"
            case .issues:
                return "\(issueDashboardFilter.title) Issues"
            }
        }
    }

    private var dashboardLoadTaskID: String {
        switch inboxMode {
        case .browse:
            switch browseScope {
            case .pullRequests:
                return "pr#\(model.lastUpdated?.timeIntervalSince1970 ?? 0)#\(model.pullRequestDashboardLastUpdated?.timeIntervalSince1970 ?? 0)"
            case .issues:
                return "issue#\(model.lastUpdated?.timeIntervalSince1970 ?? 0)#\(model.issueDashboardLastUpdated?.timeIntervalSince1970 ?? 0)"
            }
        case .inbox:
            return "inbox"
        }
    }

    private var isScopeRefreshing: Bool {
        switch inboxMode {
        case .inbox:
            return model.isRefreshing
        case .browse:
            switch browseScope {
            case .pullRequests:
                return model.isPullRequestDashboardRefreshing
            case .issues:
                return model.isIssueDashboardRefreshing
            }
        }
    }

    private var currentError: String? {
        switch inboxMode {
        case .inbox:
            return model.lastError
        case .browse:
            switch browseScope {
            case .pullRequests:
                return model.pullRequestDashboardLastError
            case .issues:
                return model.issueDashboardLastError
            }
        }
    }

    private func currentLastUpdatedText(relativeTo referenceDate: Date) -> String {
        switch inboxMode {
        case .inbox:
            return model.relativeLastUpdated(relativeTo: referenceDate)
        case .browse:
            switch browseScope {
            case .pullRequests:
                return model.relativePullRequestDashboardLastUpdated(relativeTo: referenceDate)
            case .issues:
                return model.relativeIssueDashboardLastUpdated(relativeTo: referenceDate)
            }
        }
    }

    private var selectionBinding: Binding<Set<AttentionItem.ID>> {
        Binding(
            get: { selectedItemIDs },
            set: { newValue in
                let normalizedSelection = normalizeSelection(newValue)
                let selectionChanged = selectedItemIDs != normalizedSelection
                selectedItemIDs = normalizedSelection

                if selectionChanged {
                    cancelAutoMarkReadTask()
                    pullRequestFocusState = .idle
                    reviewMergeState = .idle
                    armAutoMarkReadForCurrentSelection()
                    updateWatchedPullRequestSelection()
                }
            }
        )
    }

    private func sidebar(relativeTo referenceDate: Date) -> some View {
        VStack(spacing: 0) {
            if model.hasToken {
                sidebarHeader(relativeTo: referenceDate)
            }

            Group {
                if showsLoadingState {
                    sidebarLoadingView
                } else if !model.hasToken {
                    connectionRequiredView
                } else if displayedItems.isEmpty {
                    emptyStateView
                } else {
                    List(selection: selectionBinding) {
                        ForEach(displayedSections) { section in
                            Section {
                                sidebarRows(section.items, relativeTo: referenceDate)
                            } header: {
                                sidebarSectionHeader(
                                    title: section.title,
                                    count: section.items.count
                                )
                            }
                        }
                    }
                    .accessibilityIdentifier("inbox-list")
                    .listStyle(.sidebar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewColumnWidth(min: 360, ideal: 420)
    }

    private var sidebarLoadingView: some View {
        loadingContent
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarHeader(relativeTo _: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    scopeControls

                    Spacer()

                    Button(action: refreshCurrentScope) {
                        ZStack {
                            Image(systemName: "arrow.clockwise")
                                .opacity(isScopeRefreshing ? 0 : 1)

                            if isScopeRefreshing && !showsLoadingState {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .frame(width: 18, height: 18)
                    }
                    .disabled(isScopeRefreshing)
                    .buttonStyle(.borderless)
                    .appInteractiveHover(backgroundOpacity: 0.08, cornerRadius: 8)
                    .help("Refresh")
                }

                HStack(alignment: .center, spacing: 8) {
                    Text(summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if inboxMode == .inbox {
                        unreadFilterButton
                    }
                }

                if inboxMode == .browse {
                    dashboardFilterControls
                }

                Text(currentLastUpdatedText(relativeTo: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.showsDebugRateLimitDetails, !model.rateLimitBuckets.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Diagnostics")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let header = model.rateLimitDebugHeader(relativeTo: context.date) {
                            Text(header)
                                .font(.caption2)
                                .foregroundStyle(model.isRateLimitWarning ? .orange : .secondary)
                                .lineLimit(2)
                        }

                        ForEach(model.rateLimitBuckets, id: \.resourceKey) { bucket in
                            Text(model.rateLimitBucketSummary(for: bucket, relativeTo: context.date))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(bucket.isLow || bucket.isExhausted ? .orange : .secondary)
                                .lineLimit(2)
                        }
                    }
                }

                if let lastError = currentError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private enum ScopeTab: String, CaseIterable, Identifiable {
        case inbox
        case myPRs
        case myIssues

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inbox: return "Inbox"
            case .myPRs: return "My PRs"
            case .myIssues: return "My Issues"
            }
        }

        var iconName: String {
            switch self {
            case .inbox: return "tray"
            case .myPRs: return "arrow.triangle.pull"
            case .myIssues: return "exclamationmark.circle"
            }
        }
    }

    private var activeScopeTab: ScopeTab {
        switch inboxMode {
        case .inbox: return .inbox
        case .browse:
            return browseScope == .pullRequests ? .myPRs : .myIssues
        }
    }

    private func selectScopeTab(_ tab: ScopeTab) {
        switch tab {
        case .inbox:
            inboxMode = .inbox
        case .myPRs:
            inboxMode = .browse
            browseScope = .pullRequests
        case .myIssues:
            inboxMode = .browse
            browseScope = .issues
        }
    }

    @ViewBuilder
    private var scopeControls: some View {
        HStack(spacing: 0) {
            ForEach(ScopeTab.allCases) { tab in
                let isActive = activeScopeTab == tab
                Button {
                    selectScopeTab(tab)
                } label: {
                    Label(tab.title, systemImage: tab.iconName)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(isActive ? .white : .primary)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isActive ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dashboardFilterControls: some View {
        switch browseScope {
        case .pullRequests:
            dashboardFilterRow(title: "Pull Request Filters") {
                ForEach(PullRequestDashboardFilter.allCases) { filter in
                    dashboardFilterChip(
                        title: filter.title,
                        isSelected: pullRequestDashboardFilter == filter
                    ) {
                        pullRequestDashboardFilter = filter
                    }
                }
            }
        case .issues:
            dashboardFilterRow(title: "Issue Filters") {
                ForEach(IssueDashboardFilter.allCases) { filter in
                    dashboardFilterChip(
                        title: filter.title,
                        isSelected: issueDashboardFilter == filter
                    ) {
                        issueDashboardFilter = filter
                    }
                }
            }
        }
    }

    private func dashboardFilterRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 1)
        }
        .accessibilityLabel(title)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardFilterChip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor
                                : Color(nsColor: .controlBackgroundColor)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected
                                ? Color.accentColor.opacity(0.85)
                                : Color(nsColor: .separatorColor).opacity(0.45),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .appInteractiveHover(backgroundOpacity: isSelected ? 0 : 0.08, cornerRadius: 999)
        .accessibilityLabel("Show \(title)")
    }

    private var unreadFilterButton: some View {
        Button {
            showsUnreadOnly.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showsUnreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .imageScale(.medium)
                Text("Unread")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(showsUnreadOnly ? .white : .primary)
            .background(
                Capsule(style: .continuous)
                    .fill(showsUnreadOnly ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        showsUnreadOnly
                            ? Color.accentColor.opacity(0.85)
                            : Color(nsColor: .separatorColor).opacity(0.45),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .appInteractiveHover(backgroundOpacity: showsUnreadOnly ? 0 : 0.08, cornerRadius: 999)
        .help(showsUnreadOnly ? "Show all items" : "Show unread items")
        .accessibilityLabel(showsUnreadOnly ? "Showing unread items" : "Showing all items")
    }

    private func detailPane(relativeTo referenceDate: Date) -> some View {
        Group {
            if showsLoadingState {
                loadingDetailPlaceholder
            } else if !model.hasToken {
                connectionRequiredView
            } else if selectionActionItems.count > 1 {
                multipleSelectionView
            } else if let item = selectedItem {
                AttentionDetailView(
                    item: item,
                    itemTimestamp: item.timestamp,
                    viewerLogin: model.viewerLogin,
                    referenceDate: referenceDate,
                    pullRequestFocusState: pullRequestFocusState,
                    reviewMergeState: reviewMergeState,
                    onOpenURL: { url in
                        openRelatedURL(url, for: item)
                    },
                    onPresentWorkflowApproval: { request in
                        presentWorkflowApprovalSheet(request)
                    },
                    onPerformReviewMerge: { mergeMethod in
                        Task {
                            await performReviewMergeForSelection(mergeMethod: mergeMethod)
                        }
                    },
                    onSelectMergeMethod: { mergeMethod in
                        guard let reference = item.pullRequestReference else {
                            return
                        }

                        model.rememberPreferredMergeMethod(mergeMethod, for: reference)
                    },
                    onRetryPullRequestFocus: {
                        Task {
                            await loadPullRequestFocusForSelection(force: true)
                        }
                    }
                )
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var loadingDetailPlaceholder: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    private var connectionRequiredView: some View {
        ContentUnavailableView {
            Label("GitHub Connection Required", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("Open Settings to connect GitHub with either GitHub CLI or a personal access token.")
        } actions: {
            Button("Open Settings") {
                openSettings()
            }
            .appInteractiveHover()
        }
    }

    private var emptyStateView: some View {
        let title: String
        let description: String

        switch inboxMode {
        case .inbox:
            if showsUnreadOnly {
                title = "No unread items"
                description = "Everything currently in the inbox has been marked read."
            } else {
                title = "Inbox is clear"
                description = "Octowatch is watching GitHub, but there is nothing actionable right now."
            }
        case .browse:
            switch browseScope {
            case .pullRequests:
                title = "No pull requests"
                description = "There are no open pull requests in the \(pullRequestDashboardFilter.title) view."
            case .issues:
                title = "No issues"
                description = "There are no open issues in the \(issueDashboardFilter.title) view."
            }
        }

        return ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle")
        } description: {
            Text(description)
        }
    }

    private var summaryLine: String {
        if inboxMode == .browse {
            switch browseScope {
            case .pullRequests:
                return dashboardSummaryLine(
                    count: scopedItems.count,
                    noun: "pull request",
                    filterTitle: pullRequestDashboardFilter.title
                )
            case .issues:
                return dashboardSummaryLine(
                    count: scopedItems.count,
                    noun: "issue",
                    filterTitle: issueDashboardFilter.title
                )
            }
        }

        let totalItemCount = scopedItems.count
        let unreadCount = scopedItems.filter(\.isUnread).count
        let yourTurnCount = scopedYourTurnItems.count
        let displayedCount = displayedItems.count
        let displayedYourTurnCount = displayedYourTurnItems.count
        let itemLabel = itemCountLabel(for: totalItemCount)
        let unreadLabel = unreadCount == 1
            ? "1 unread"
            : "\(unreadCount) unread"

        if showsUnreadOnly {
            let unreadSummary = unreadCountLabel(for: displayedCount)

            guard displayedYourTurnCount > 0 else {
                return unreadSummary
            }

            let actionSummary = displayedYourTurnCount == 1
                ? "1 action item"
                : "\(displayedYourTurnCount) action items"
            return "\(unreadSummary) · \(actionSummary)"
        }

        guard yourTurnCount > 0 else {
            return "\(itemLabel) · \(unreadLabel)"
        }

        let actionSummary = yourTurnCount == 1 ? "1 action item" : "\(yourTurnCount) action items"
        return "\(actionSummary) · \(itemLabel) · \(unreadLabel)"
    }

    private func dashboardSummaryLine(
        count: Int,
        noun: String,
        filterTitle: String
    ) -> String {
        let label = count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
        return "\(filterTitle) · \(label)"
    }

    private func sidebarSectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)

            Text("\(count)")
                .foregroundStyle(.tertiary)
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func sidebarRows(
        _ items: [AttentionItem],
        relativeTo referenceDate: Date
    ) -> some View {
        ForEach(items) { item in
            AttentionSidebarRow(
                item: item,
                viewerLogin: model.viewerLogin,
                relativeTimestamp: relativeFormatter.localizedString(
                    for: item.timestamp,
                    relativeTo: referenceDate
                ),
                onOpenWorkflowApproval: {
                    presentWorkflowApprovalSheet($0)
                }
            )
            .contentShape(Rectangle())
            .contextMenu {
                selectionContextMenu(for: contextMenuItems(for: item))
            }
            .tag(item.id)
        }
    }

    private var multipleSelectionView: some View {
        ContentUnavailableView {
            Label("\(selectionActionItems.count) Items Selected", systemImage: "checklist")
        } description: {
            Text(
                showsReadActions
                    ? "Use the toolbar or the right-click menu to open items, update their read state, or ignore them."
                    : "Use the toolbar or the right-click menu to open items or ignore them."
            )
        }
    }

    private func syncSelection() {
        cancelAutoSelectionTask()

        let normalizedSelection = normalizeSelection(selectedItemIDs)
        let selectionChanged = selectedItemIDs != normalizedSelection
        selectedItemIDs = normalizedSelection

        if selectionChanged {
            cancelAutoMarkReadTask()
            pullRequestFocusState = .idle
            reviewMergeState = .idle
            armAutoMarkReadForCurrentSelection()
        }

        updateWatchedPullRequestSelection()

        if selectedItemIDs.isEmpty, let firstItemID = displayedItems.first?.id {
            scheduleAutoSelection(firstItemID)
        }
    }

    private func updateWatchedPullRequestSelection() {
        model.setWatchedPullRequest(selectedItem)
    }

    private func normalizeSelection(_ selection: Set<AttentionItem.ID>) -> Set<AttentionItem.ID> {
        let displayedItemIDs = Set(displayedItems.map(\.id))
        return selection.intersection(displayedItemIDs)
    }

    private func itemCountLabel(for count: Int) -> String {
        let noun = count == 1 ? "item" : "items"
        return "\(count) \(noun)"
    }

    private func unreadCountLabel(for count: Int) -> String {
        let noun = count == 1 ? "item" : "items"
        return "Showing \(count) unread \(noun)"
    }

    private func loadDashboardIfNeeded() async {
        guard inboxMode == .browse else {
            return
        }

        switch browseScope {
        case .pullRequests:
            await model.ensurePullRequestDashboardLoaded()
        case .issues:
            await model.ensureIssueDashboardLoaded()
        }
    }

    private func refreshCurrentScope() {
        Task {
            switch inboxMode {
            case .browse:
                switch browseScope {
                case .pullRequests:
                    await model.refreshPullRequestDashboard(force: true)
                case .issues:
                    await model.refreshIssueDashboard(force: true)
                }
            case .inbox:
                await model.forceRefresh()
            }
        }
    }

    private func refreshSelection(_ item: AttentionItem) async {
        switch inboxMode {
        case .browse:
            switch browseScope {
            case .pullRequests:
                await model.refreshPullRequestDashboard(force: true)
            case .issues:
                await model.refreshIssueDashboard(force: true)
            }
        case .inbox:
            await model.forceRefresh(item: item)
        }
    }

    private func scheduleAutoSelection(_ itemID: AttentionItem.ID) {
        autoSelectionTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else {
                return
            }

            guard selectedItemIDs.isEmpty, displayedItems.contains(where: { $0.id == itemID }) else {
                return
            }

            selectedItemIDs = [itemID]
            pullRequestFocusState = .idle
            reviewMergeState = .idle
            armAutoMarkReadForCurrentSelection()
            updateWatchedPullRequestSelection()
        }
    }

    private func openRelatedURL(_ url: URL, for item: AttentionItem) {
        cancelAutoMarkReadTask()
        if item.supportsReadState {
            model.markItemAsRead(item)
        }
        openURL(url)
    }

    private func openSelection(_ items: [AttentionItem]) {
        cancelAutoMarkReadTask()
        model.markItemsAsRead(items.filter(\.supportsReadState))

        for item in items {
            openURL(item.url)
        }
    }

    private func markSelectionAsRead(_ items: [AttentionItem]) {
        cancelAutoMarkReadTask()
        model.markItemsAsRead(items)
    }

    private func markSelectionAsUnread(_ items: [AttentionItem]) {
        cancelAutoMarkReadTask()
        model.markItemsAsUnread(items)
    }

    private func performPrimaryReadAction(for items: [AttentionItem]) {
        if items.contains(where: \.isUnread) {
            markSelectionAsRead(items)
        } else {
            markSelectionAsUnread(items)
        }
    }

    private func ignoreSelection(_ items: [AttentionItem]) {
        cancelAutoMarkReadTask()
        model.ignore(items)
    }

    private func presentWorkflowApprovalSheet(
        _ request: WorkflowApprovalSheetRequest
    ) {
        cancelAutoMarkReadTask()
        if let sourceItem = request.sourceItem, sourceItem.supportsReadState {
            model.markItemAsRead(sourceItem)
        }
        workflowApprovalSheetRequest = request
    }

    private func workflowApprovalRequests(for items: [AttentionItem]) -> [WorkflowApprovalSheetRequest] {
        var requests = [WorkflowApprovalSheetRequest]()
        var seen = Set<String>()

        for item in items {
            guard let request = WorkflowApprovalSheetRequest(item: item) else {
                continue
            }

            guard seen.insert(request.id).inserted else {
                continue
            }

            requests.append(request)
        }

        return requests
    }

    private func workflowApprovalURLs(for items: [AttentionItem]) -> [URL] {
        workflowApprovalRequests(for: items).map(\.target.url)
    }

    private func openWorkflowApprovalsOnGitHub(for items: [AttentionItem]) {
        let approvalURLs = workflowApprovalURLs(for: items)
        guard !approvalURLs.isEmpty else {
            return
        }

        cancelAutoMarkReadTask()
        model.markItemsAsRead(
            items.filter { $0.supportsReadState && $0.workflowApprovalURL != nil }
        )

        for approvalURL in approvalURLs {
            openURL(approvalURL)
        }
    }

    private func contextMenuItems(for item: AttentionItem) -> [AttentionItem] {
        if selectedItemIDs.contains(item.id) {
            return selectionActionItems
        }

        return [item]
    }

    @ViewBuilder
    private func selectionContextMenu(for items: [AttentionItem]) -> some View {
        let approvalRequests = workflowApprovalRequests(for: items)
        let approvalURLs = workflowApprovalURLs(for: items)
        let readEligibleItems = items.filter(\.supportsReadState)

        if approvalRequests.count == 1, let approvalRequest = approvalRequests.first {
            Button {
                presentWorkflowApprovalSheet(approvalRequest)
            } label: {
                Label(
                    "Review Deployment",
                    systemImage: "hand.raised"
                )
            }

            Button {
                openWorkflowApprovalsOnGitHub(for: items)
            } label: {
                Label("Open Approval on GitHub", systemImage: "arrow.up.right.square")
            }

            Divider()
        } else if approvalURLs.count > 1 {
            Button {
                openWorkflowApprovalsOnGitHub(for: items)
            } label: {
                Label("Open Approvals on GitHub", systemImage: "arrow.up.right.square")
            }

            Divider()
        }

        Button {
            openSelection(items)
        } label: {
            Label("Open", systemImage: "safari")
        }

        if !readEligibleItems.isEmpty {
            Button {
                markSelectionAsRead(readEligibleItems)
            } label: {
                Label("Mark as Read", systemImage: "circle")
            }
            .disabled(!readEligibleItems.contains(where: \.isUnread))

            Button {
                markSelectionAsUnread(readEligibleItems)
            } label: {
                Label("Mark as Unread", systemImage: "circle.fill")
            }
            .disabled(!readEligibleItems.contains(where: { !$0.isUnread }))

            Divider()
        }

        Button {
            ignoreSelection(items)
        } label: {
            Label("Ignore", systemImage: "eye.slash")
        }
    }

    private func armAutoMarkReadForCurrentSelection() {
        cancelAutoMarkReadTask()

        guard let item = selectedItem,
            item.supportsReadState,
            item.isUnread,
            let autoMarkReadDelay = model.autoMarkReadDelay else {
            return
        }

        let expectedID = item.id
        autoMarkReadTask = Task {
            try? await Task.sleep(for: autoMarkReadDelay)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let currentItem = selectedItem,
                    currentItem.id == expectedID,
                    currentItem.isUnread else {
                    return
                }

                model.markItemAsRead(currentItem)
            }
        }
    }

    private func performReviewMergeForSelection(mergeMethod: PullRequestMergeMethod?) async {
        guard
            let item = selectedItem,
            case let .loaded(focus) = pullRequestFocusState,
            let reviewMergeAction = focus.reviewMergeAction
        else {
            return
        }

        await MainActor.run {
            reviewMergeState = .running
        }

        do {
            let outcome = try await model.approveAndMergePullRequest(
                for: item,
                requiresApproval: reviewMergeAction.requiresApproval,
                mergeMethod: mergeMethod ?? reviewMergeAction.mergeMethod
            )
            await MainActor.run {
                reviewMergeState = .succeeded(outcome)
            }
            await loadPullRequestFocusForSelection(force: true)
            model.refreshNow()
        } catch {
            await MainActor.run {
                reviewMergeState = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelAutoMarkReadTask() {
        autoMarkReadTask?.cancel()
        autoMarkReadTask = nil
    }

    private func cancelAutoSelectionTask() {
        autoSelectionTask?.cancel()
        autoSelectionTask = nil
    }

    private func loadPullRequestFocusForSelection(force: Bool = false) async {
        guard let item = selectedItem, item.pullRequestReference != nil, model.hasToken else {
            await MainActor.run {
                pullRequestFocusState = .idle
            }
            return
        }

        let expectedItemID = item.id
        await MainActor.run {
            pullRequestFocusState = .loading
        }

        do {
            let focus = try await model.fetchPullRequestFocus(for: item, force: force)
            await MainActor.run {
                guard selectedItem?.id == expectedItemID else {
                    return
                }

                if let focus {
                    pullRequestFocusState = .loaded(focus)
                } else {
                    pullRequestFocusState = .idle
                }
            }
        } catch {
            await MainActor.run {
                guard selectedItem?.id == expectedItemID else {
                    return
                }

                pullRequestFocusState = .failed(error.localizedDescription)
            }
        }
    }
}

private enum PullRequestFocusLoadState: Equatable {
    case idle
    case loading
    case loaded(PullRequestFocus)
    case failed(String)
}

private enum PullRequestReviewMergeState: Equatable {
    case idle
    case running
    case succeeded(PullRequestMutationOutcome)
    case failed(String)
}

private struct AttentionSidebarRow: View {
    let item: AttentionItem
    let viewerLogin: String?
    let relativeTimestamp: String
    let onOpenWorkflowApproval: (WorkflowApprovalSheetRequest) -> Void

    private var contextLine: String {
        let typeSummary = item.type.nativeNotificationTitle
        if let repo = item.repository {
            return "\(repo) · \(typeSummary)"
        }
        return typeSummary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .opacity(item.isUnread ? 1 : 0)

            EventBadge(type: item.type, secondaryType: item.secondaryIndicatorType)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .accessibilityIdentifier("sidebar-item-title-\(item.id)")
                    .accessibilityValue(item.isUnread ? "unread" : "read")

                HStack(spacing: 0) {
                    Text(contextLine)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    Text(relativeTimestamp)
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AttentionDetailView: View {
    let item: AttentionItem
    let itemTimestamp: Date
    let viewerLogin: String?
    let referenceDate: Date
    let pullRequestFocusState: PullRequestFocusLoadState
    let reviewMergeState: PullRequestReviewMergeState
    let onOpenURL: (URL) -> Void
    let onPresentWorkflowApproval: (WorkflowApprovalSheetRequest) -> Void
    let onPerformReviewMerge: (PullRequestMergeMethod?) -> Void
    let onSelectMergeMethod: (PullRequestMergeMethod) -> Void
    let onRetryPullRequestFocus: () -> Void

    private var visibleEvidence: [AttentionEvidence] {
        item.detail.evidence.filter { evidence in
            evidence.id != "actor" && evidence.id != "repository"
        }
    }

    private var visibleUpdates: [AttentionUpdate] {
        item.detail.updates
    }

    private var loadedPullRequestFocus: PullRequestFocus? {
        guard case let .loaded(focus) = pullRequestFocusState else {
            return nil
        }

        return focus
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var primaryHeaderTimestamp: Date {
        PullRequestHeaderTimestampPolicy.primaryTimestamp(
            resolution: loadedPullRequestFocus?.resolution ?? .open,
            itemTimestamp: itemTimestamp,
            mergedAt: loadedPullRequestFocus?.mergedAt
        )
    }

    private var primaryHeaderTimestampText: String {
        Self.relativeFormatter.localizedString(
            for: primaryHeaderTimestamp,
            relativeTo: referenceDate
        )
    }

    private var primaryHeaderTimestampHelp: String {
        Self.absoluteFormatter.string(from: primaryHeaderTimestamp)
    }

    private var secondaryHeaderTimestampText: String? {
        guard
            PullRequestHeaderTimestampPolicy.shouldShowLastUpdate(
                resolution: loadedPullRequestFocus?.resolution ?? .open,
                itemTimestamp: itemTimestamp,
                mergedAt: loadedPullRequestFocus?.mergedAt,
                referenceDate: referenceDate
            )
        else {
            return nil
        }

        let relativeLastUpdate = Self.relativeFormatter.localizedString(
            for: itemTimestamp,
            relativeTo: referenceDate
        )
        return "last update \(relativeLastUpdate)"
    }

    private var secondaryHeaderTimestampHelp: String {
        Self.absoluteFormatter.string(from: itemTimestamp)
    }

    private var headerPillTitleOverride: String? {
        if let contextPillTitle = item.detail.contextPillTitle {
            return contextPillTitle
        }

        switch item.type {
        case .assignedPullRequest:
            return "Assigned to you"
        case .authoredPullRequest, .authoredIssue:
            return "Created by you"
        case .reviewedPullRequest:
            return "Reviewed by you"
        case .commentedPullRequest, .commentedIssue:
            return "Commented on by you"
        case .readyToMerge:
            return "Your PR was approved"
        case .pullRequestMergeConflicts:
            return "Your PR has conflicts"
        case .pullRequestFailedChecks:
            return "Your PR has failed checks"
        case .assignedIssue:
            return "Assigned to you"
        default:
            return nil
        }
    }

    private var displayedLabels: [GitHubLabel] {
        if let focus = loadedPullRequestFocus, !focus.labels.isEmpty {
            return focus.labels
        }

        return item.labels
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 18) {
                        EventBadge(
                            type: item.type,
                            secondaryType: item.secondaryIndicatorType,
                            size: 40
                        )

                        DetailTitleLinkButton(
                            title: item.title,
                            action: {
                                onOpenURL(item.url)
                            }
                        )
                    }

                    if item.repository != nil || !displayedLabels.isEmpty {
                        MetadataWrapLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                            if let repository = item.repository {
                                RepositoryMetadataView(
                                    repository: repository,
                                    repositoryURL: item.repositoryURL,
                                    onOpenURL: onOpenURL
                                )
                            }

                            ForEach(displayedLabels) { label in
                                GitHubLabelChip(
                                    label: label,
                                    actionURL: item.labelSearchURL(for: label),
                                    onOpenURL: onOpenURL
                                )
                            }
                        }
                    }

                    if let focus = loadedPullRequestFocus {
                        HStack(alignment: .center, spacing: 10) {
                            AttentionTypePill(
                                type: item.type,
                                titleOverride: headerPillTitleOverride
                            )

                            ForEach(focus.headerFacts.indices, id: \.self) { index in
                                Text("·")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)

                                PullRequestHeaderFactView(
                                    fact: focus.headerFacts[index],
                                    viewerLogin: viewerLogin,
                                    onOpenURL: onOpenURL
                                )
                            }

                            Text("·")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)

                            Text(primaryHeaderTimestampText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .help(primaryHeaderTimestampHelp)

                            if let secondaryHeaderTimestampText {
                                Text("·")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)

                                Text(secondaryHeaderTimestampText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .help(secondaryHeaderTimestampHelp)
                            }
                        }
                    } else {
                        HStack(alignment: .center, spacing: 10) {
                            AttentionTypePill(type: item.type, titleOverride: headerPillTitleOverride)

                            if let actor = item.actor {
                                Text(item.actorRelationshipLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                DetailActorAvatar(actor: actor, size: 20)

                                ActorLinkLabel(
                                    actor: actor,
                                    viewerLogin: viewerLogin,
                                    onOpenURL: onOpenURL
                                )
                            }

                            Text("·")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)

                            Text(primaryHeaderTimestampText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .help(primaryHeaderTimestampHelp)
                        }
                    }
                }

                if item.pullRequestReference == nil && !visibleEvidence.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(visibleEvidence) { evidence in
                                DetailEvidenceRow(
                                    evidence: evidence,
                                    viewerLogin: viewerLogin,
                                    onOpenURL: onOpenURL
                                )
                            }
                        }
                    }
                }

                pullRequestFocusContent

                if !visibleUpdates.isEmpty {
                    DetailCard(title: "All updates") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(visibleUpdates) { update in
                                AttentionUpdateRow(
                                    update: update,
                                    sourceItem: item,
                                    viewerLogin: viewerLogin,
                                    referenceDate: referenceDate,
                                    onOpenURL: onOpenURL,
                                    onPresentWorkflowApproval: onPresentWorkflowApproval
                                )
                            }
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var pullRequestFocusContent: some View {
        switch pullRequestFocusState {
        case .idle:
            EmptyView()
        case .loading:
            if item.pullRequestReference != nil {
                DetailCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Loading pull request details…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case let .failed(message):
            if item.pullRequestReference != nil {
                DetailCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Could not load pull request details")
                            .font(.headline)

                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Retry") {
                            onRetryPullRequestFocus()
                        }
                        .appInteractiveHover()
                    }
                }
            }
        case let .loaded(focus):
            PullRequestFocusView(
                focus: focus,
                sourceItem: item,
                referenceDate: referenceDate,
                reviewMergeState: reviewMergeState,
                onOpenURL: onOpenURL,
                onPresentWorkflowApproval: onPresentWorkflowApproval,
                onPerformReviewMerge: onPerformReviewMerge,
                onSelectMergeMethod: onSelectMergeMethod
            )
        }
    }
}

private struct IgnoreUndoBanner: View {
    let state: IgnoreUndoState
    let onUndo: () -> Void
    let onDismiss: () -> Void

    private var title: String {
        if state.subjects.count == 1, let ignoredItem = state.primarySubject {
            return "Ignored \(ignoredItem.title)"
        }

        return "Ignored \(state.subjects.count) items"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                )

            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            ToastUndoButton(action: onUndo)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .appInteractiveHover(backgroundOpacity: 0.08, cornerRadius: 999)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
}

private struct ToastUndoButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("Undo")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isHovering ? Color.accentColor.opacity(0.92) : Color.accentColor)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(isHovering ? 0.3 : 0.14), lineWidth: 1)
                )
                .shadow(
                    color: Color.accentColor.opacity(isHovering ? 0.28 : 0.18),
                    radius: isHovering ? 8 : 4,
                    y: isHovering ? 3 : 2
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .appLinkHover()
        .help("Undo ignore")
    }
}

private struct DetailTitleLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "arrow.up.right.square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appLinkHover()
        .help("Open on GitHub")
    }
}

private struct DetailEvidenceRow: View {
    let evidence: AttentionEvidence
    let viewerLogin: String?
    let onOpenURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: evidence.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(evidence.title)
                    .font(.subheadline.weight(.semibold))

                if let detail = evidence.detail {
                    Text(
                        AttentionViewerPresentationPolicy.personalizing(
                            detail,
                            viewerLogin: viewerLogin
                        )
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if let url = evidence.url {
                Button("Open") {
                    onOpenURL(url)
                }
                .buttonStyle(.link)
                .appLinkHover()
            }
        }
    }
}

private struct DetailCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }
}

private struct AttentionUpdateRow: View {
    let update: AttentionUpdate
    let sourceItem: AttentionItem
    let viewerLogin: String?
    let referenceDate: Date
    let onOpenURL: (URL) -> Void
    let onPresentWorkflowApproval: (WorkflowApprovalSheetRequest) -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: update.type.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(update.type.badgeForeground)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(update.title)
                    .font(.subheadline.weight(.semibold))

                if detailPresentation.hasVisibleContent {
                    HStack(alignment: .center, spacing: 6) {
                        if let actorPresentation = detailPresentation.actor {
                            Text(actorPresentation.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if actorPresentation.showsBotBadge, let actor = update.actor {
                                BotAccountChip(login: actor.login, compact: true)
                            }
                        }

                        if detailPresentation.actor != nil, let detail = detailPresentation.detail {
                            Text("·")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)

                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let detail = detailPresentation.detail {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(Self.relativeFormatter.localizedString(for: update.timestamp, relativeTo: referenceDate))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            if let workflowApprovalRequest = WorkflowApprovalSheetRequest(
                update: update,
                sourceItem: sourceItem
            ) {
                Button("Review") {
                    onPresentWorkflowApproval(workflowApprovalRequest)
                }
                .buttonStyle(.link)
                .appInteractiveHover(scale: 0.992, opacity: 0.99)
            } else if let url = update.url {
                Button("Open") {
                    onOpenURL(url)
                }
                .buttonStyle(.link)
                .appLinkHover()
            }
        }
    }

    private var detailPresentation: AttentionViewerPresentationPolicy.UpdatePresentation {
        AttentionViewerPresentationPolicy.updatePresentation(
            actor: update.actor,
            detail: update.detail,
            viewerLogin: viewerLogin
        )
    }
}

private struct PullRequestFocusView: View {
    let focus: PullRequestFocus
    let sourceItem: AttentionItem
    let referenceDate: Date
    let reviewMergeState: PullRequestReviewMergeState
    let onOpenURL: (URL) -> Void
    let onPresentWorkflowApproval: (WorkflowApprovalSheetRequest) -> Void
    let onPerformReviewMerge: (PullRequestMergeMethod?) -> Void
    let onSelectMergeMethod: (PullRequestMergeMethod) -> Void

    @State private var selectedMergeMethod: PullRequestMergeMethod?

    init(
        focus: PullRequestFocus,
        sourceItem: AttentionItem,
        referenceDate: Date,
        reviewMergeState: PullRequestReviewMergeState,
        onOpenURL: @escaping (URL) -> Void,
        onPresentWorkflowApproval: @escaping (WorkflowApprovalSheetRequest) -> Void,
        onPerformReviewMerge: @escaping (PullRequestMergeMethod?) -> Void,
        onSelectMergeMethod: @escaping (PullRequestMergeMethod) -> Void
    ) {
        self.focus = focus
        self.sourceItem = sourceItem
        self.referenceDate = referenceDate
        self.reviewMergeState = reviewMergeState
        self.onOpenURL = onOpenURL
        self.onPresentWorkflowApproval = onPresentWorkflowApproval
        self.onPerformReviewMerge = onPerformReviewMerge
        self.onSelectMergeMethod = onSelectMergeMethod
        _selectedMergeMethod = State(initialValue: focus.reviewMergeAction?.preferredMergeMethod)
    }

    private var displayedMergeOutcome: PullRequestMutationOutcome? {
        if focus.resolution == .merged {
            return .merged
        }

        if let outcome = focus.reviewMergeAction?.outcome {
            return outcome
        }

        if case let .succeeded(outcome) = reviewMergeState {
            return outcome
        }

        return nil
    }

    private var reviewMergeButtonTint: Color? {
        if let outcome = displayedMergeOutcome {
            switch outcome {
            case .merged:
                return .mint
            case .queued:
                return .orange
            }
        }

        if focus.reviewMergeAction?.isEnabled == true {
            return .green
        }

        return nil
    }

    private var showsTerminalReviewMergeAction: Bool {
        focus.reviewMergeAction != nil && displayedMergeOutcome != nil
    }

    private var isReviewMergeActionInteractive: Bool {
        guard let reviewMergeAction = focus.reviewMergeAction else {
            return false
        }

        return reviewMergeState != .running &&
            displayedMergeOutcome == nil &&
            reviewMergeAction.isEnabled &&
            resolvedReviewMergeMethod != nil
    }

    private var shouldShowMergeMethodSelector: Bool {
        guard let reviewMergeAction = focus.reviewMergeAction else {
            return false
        }

        return displayedMergeOutcome == nil && reviewMergeAction.needsMergeMethodSelection
    }

    private var reviewMergeButtonTitle: String {
        guard let reviewMergeAction = focus.reviewMergeAction else {
            return ""
        }

        guard let mergeMethod = resolvedReviewMergeMethod else {
            return reviewMergeAction.title
        }

        if reviewMergeAction.requiresApproval {
            return "Approve and \(mergeMethod.buttonTitle.lowercased())"
        }

        return mergeMethod.buttonTitle
    }

    private var resolvedReviewMergeMethod: PullRequestMergeMethod? {
        guard let reviewMergeAction = focus.reviewMergeAction else {
            return nil
        }

        if reviewMergeAction.needsMergeMethodSelection {
            return selectedMergeMethod ?? reviewMergeAction.preferredMergeMethod
        }

        return reviewMergeAction.mergeMethod
    }

    private var displayedContextBadges: [PullRequestContextBadge] {
        focus.displayedContextBadges(excluding: sourceItem.type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !displayedContextBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayedContextBadges) { badge in
                            PullRequestContextBadgeView(badge: badge)
                        }
                    }
                }
            }

            if focus.reviewMergeAction != nil || !focus.actions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if let reviewMergeAction = focus.reviewMergeAction {
                            if shouldShowMergeMethodSelector {
                                Menu {
                                    ForEach(reviewMergeAction.allowedMergeMethods, id: \.self) { method in
                                        Button {
                                            selectMergeMethod(method)
                                        } label: {
                                            if resolvedReviewMergeMethod == method {
                                                Label(method.selectorTitle, systemImage: "checkmark")
                                            } else {
                                                Text(method.selectorTitle)
                                            }
                                        }
                                    }
                                } label: {
                                    reviewMergeButtonLabel(reviewMergeAction: reviewMergeAction)
                                } primaryAction: {
                                    onPerformReviewMerge(resolvedReviewMergeMethod)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(reviewMergeButtonTint)
                                .disabled(!isReviewMergeActionInteractive)
                                .modifier(
                                    ConditionalInteractiveHoverModifier(
                                        isEnabled: isReviewMergeActionInteractive
                                    )
                                )
                                .help("Merge this pull request or choose a different merge method")
                            } else {
                                Button {
                                    onPerformReviewMerge(resolvedReviewMergeMethod)
                                } label: {
                                    reviewMergeButtonLabel(reviewMergeAction: reviewMergeAction)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(reviewMergeButtonTint)
                                .disabled(!isReviewMergeActionInteractive)
                                .modifier(
                                    ConditionalInteractiveHoverModifier(
                                        isEnabled: isReviewMergeActionInteractive
                                    )
                                )
                            }
                        }

                        ForEach(focus.actions) { action in
                            if action.isPrimary {
                                Button {
                                    onOpenURL(action.url)
                                } label: {
                                    Label(action.title, systemImage: action.iconName)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(action.id == "merge" ? .green : nil)
                                .appInteractiveHover()
                            } else {
                                Button {
                                    onOpenURL(action.url)
                                } label: {
                                    Label(action.title, systemImage: action.iconName)
                                }
                                .buttonStyle(.bordered)
                                .appInteractiveHover()
                            }
                        }
                    }
                }

                if let reviewMergeAction = focus.reviewMergeAction {
                    if case let .failed(message) = reviewMergeState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if showsTerminalReviewMergeAction {
                    } else if let disabledReason = reviewMergeAction.disabledReason,
                        !reviewMergeAction.isEnabled {
                        Text(disabledReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let statusSummary = focus.statusSummary, !showsTerminalReviewMergeAction {
                PullRequestStatusSummaryCard(summary: statusSummary)
            }

            if let postMergeWorkflowPreview = focus.postMergeWorkflowPreview {
                DetailCard(title: postMergeWorkflowPreview.title) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(postMergeWorkflowPreview.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(postMergeWorkflowPreview.workflows) { workflow in
                                PullRequestPostMergeWorkflowRow(
                                    workflow: workflow,
                                    sourceItem: sourceItem,
                                    referenceDate: referenceDate,
                                    onOpenURL: onOpenURL,
                                    onPresentWorkflowApproval: onPresentWorkflowApproval
                                )
                            }
                        }

                        if let footnote = postMergeWorkflowPreview.footnote {
                            HStack(alignment: .top, spacing: 6) {
                                Text(footnote)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let footnoteHelpText = postMergeWorkflowPreview.footnoteHelpText {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .help(footnoteHelpText)
                                }
                            }
                        }
                    }
                }
            }

            if focus.sections.isEmpty {
                if focus.statusSummary == nil {
                    DetailCard {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: emptyStateIconName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(emptyStateColor)
                                .frame(width: 24, height: 24)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(focus.emptyStateTitle)
                                    .font(.headline)

                                Text(focus.emptyStateDetail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                ForEach(focus.sections) { section in
                    DetailCard(title: section.title) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(section.items) { entry in
                                PullRequestFocusEntryRow(
                                    entry: entry,
                                    referenceDate: referenceDate,
                                    onOpenURL: onOpenURL
                                )
                            }
                        }
                    }
                }
            }

            if let descriptionHTML = focus.descriptionHTML {
                DetailCard(title: "Description") {
                    PullRequestDescriptionView(
                        html: descriptionHTML,
                        baseURL: focus.reference.pullRequestURL
                    )
                }
            }
        }
        .onChange(of: focus.reviewMergeAction?.allowedMergeMethods) { _, _ in
            selectedMergeMethod = focus.reviewMergeAction?.preferredMergeMethod
        }
    }

    @ViewBuilder
    private func reviewMergeButtonLabel(reviewMergeAction: PullRequestReviewMergeAction) -> some View {
        if reviewMergeState == .running {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(
                    reviewMergeAction.requiresApproval
                        ? "Approving and Merging…"
                        : "Merging…"
                )
            }
        } else if let outcome = displayedMergeOutcome {
            Label(
                outcome.buttonTitle,
                systemImage: outcome.iconName
            )
        } else {
            Label(
                reviewMergeButtonTitle,
                systemImage: reviewMergeAction.outcome?.iconName
                    ?? (reviewMergeAction.requiresApproval
                        ? "checkmark.circle.badge.questionmark"
                        : "checkmark.circle")
            )
        }
    }

    private func selectMergeMethod(_ mergeMethod: PullRequestMergeMethod) {
        selectedMergeMethod = mergeMethod
        onSelectMergeMethod(mergeMethod)
    }

    private var emptyStateIconName: String {
        switch focus.mode {
        case .authored:
            return "checkmark.circle.fill"
        case .participating, .generic:
            return "checkmark.circle"
        }
    }

    private var emptyStateColor: Color {
        switch focus.mode {
        case .authored:
            return .green
        case .participating, .generic:
            return .secondary
        }
    }
}

private struct PullRequestContextBadgeView: View {
    let badge: PullRequestContextBadge

    var body: some View {
        Label(badge.title, systemImage: badge.iconName)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.14))
            )
            .foregroundStyle(accentColor)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(accentColor.opacity(0.2), lineWidth: 1)
            )
    }

    private var accentColor: Color {
        color(for: badge.accent)
    }
}

private struct PullRequestHeaderFactView: View {
    let fact: PullRequestHeaderFact
    let viewerLogin: String?
    let onOpenURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(fact.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DetailActorAvatar(actor: fact.actor, size: 20)

            ActorLinkLabel(
                actor: fact.actor,
                viewerLogin: viewerLogin,
                onOpenURL: onOpenURL
            )

            if let overflowLabel = fact.overflowLabel {
                Text(overflowLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ActorLinkLabel: View {
    let actor: AttentionActor
    let viewerLogin: String?
    let onOpenURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(presentation.label) {
                onOpenURL(actor.profileURL)
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.plain)
            .appLinkHover()
            .foregroundStyle(presentation.showsBotBadge ? Color.primary : Color.accentColor)

            if presentation.showsBotBadge {
                BotAccountChip(login: actor.login)
            }
        }
    }

    private var presentation: AttentionViewerPresentationPolicy.ActorPresentation {
        AttentionViewerPresentationPolicy.actorPresentation(
            for: actor,
            viewerLogin: viewerLogin
        )
    }
}

private struct PullRequestStatusSummaryCard: View {
    let summary: PullRequestStatusSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: summary.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.title)
                    .font(.headline)

                Text(summary.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accentColor.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var accentColor: Color {
        color(for: summary.accent)
    }
}

private struct PullRequestDescriptionView: View {
    let html: String
    let baseURL: URL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RichHTMLTextView(
            html: htmlDocument,
            baseURL: baseURL
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var htmlDocument: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: \(colorScheme == .dark ? "dark" : "light");
              --text: \(colorScheme == .dark ? "#f5f5f7" : "#1c1c1e");
              --muted: \(colorScheme == .dark ? "#a1a1aa" : "#6b7280");
              --link: \(colorScheme == .dark ? "#6cb6ff" : "#0969da");
              --border: \(colorScheme == .dark ? "#3f3f46" : "#d0d7de");
              --surface: \(colorScheme == .dark ? "#18181b" : "#f6f8fa");
              --surface-strong: \(colorScheme == .dark ? "#27272a" : "#ffffff");
              --warning-bg: \(colorScheme == .dark ? "#3a2a0c" : "#fff8c5");
              --warning-border: \(colorScheme == .dark ? "#7c5e10" : "#d4a72c");
            }
            body {
              margin: 0;
              color: var(--text);
              font: 14px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              word-wrap: break-word;
            }
            p, ul, ol, pre, table, blockquote, hr, h1, h2, h3, h4, h5, h6 {
              margin: 0 0 12px 0;
            }
            a {
              color: var(--link);
              text-decoration: none;
            }
            a:hover {
              text-decoration: underline;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              background: var(--surface-strong);
              border: 1px solid var(--border);
              border-radius: 10px;
              overflow: hidden;
              display: table;
            }
            th, td {
              padding: 8px 10px;
              border: 1px solid var(--border);
              text-align: left;
              vertical-align: top;
            }
            code {
              font: 12px/1.5 "SF Mono", SFMono-Regular, ui-monospace, Menlo, monospace;
              background: var(--surface);
              padding: 2px 5px;
              border-radius: 6px;
            }
            pre {
              padding: 12px;
              border-radius: 10px;
              background: var(--surface);
              overflow-x: auto;
            }
            pre code {
              padding: 0;
              background: transparent;
            }
            hr {
              border: 0;
              border-top: 1px solid var(--border);
            }
            blockquote {
              padding-left: 12px;
              border-left: 3px solid var(--border);
              color: var(--muted);
            }
            .markdown-alert {
              padding: 12px 14px;
              border-radius: 12px;
              border: 1px solid var(--warning-border);
              background: var(--warning-bg);
              margin-bottom: 12px;
            }
            .markdown-alert-title {
              margin: 0 0 6px 0;
              font-weight: 700;
            }
            .markdown-alert svg {
              display: none;
            }
            .contains-task-list {
              padding-left: 0;
              list-style: none;
            }
            .task-list-item-checkbox {
              margin-right: 8px;
            }
            markdown-accessiblity-table {
              display: block;
              overflow-x: auto;
            }
          </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }
}

private struct RichHTMLTextView: NSViewRepresentable {
    let html: String
    let baseURL: URL

    func makeNSView(context: Context) -> SelfSizingTextView {
        let textView = SelfSizingTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return textView
    }

    func updateNSView(_ textView: SelfSizingTextView, context: Context) {
        let attributed = (try? attributedHTML()) ?? NSAttributedString(string: "")
        textView.textStorage?.setAttributedString(attributed)
        textView.invalidateIntrinsicContentSize()
    }

    private func attributedHTML() throws -> NSAttributedString {
        guard let data = html.data(using: .utf8) else {
            return NSAttributedString(string: "")
        }

        return try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
                .baseURL: baseURL
            ],
            documentAttributes: nil
        )
    }
}

private final class SelfSizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return super.intrinsicContentSize
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: ceil(usedRect.height + textContainerInset.height * 2)
        )
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }
}

struct WorkflowApprovalSheetRequest: Identifiable, Hashable {
    let target: WorkflowApprovalTarget
    let sourceItem: AttentionItem?
    let title: String
    let subtitle: String?

    var id: String {
        target.id
    }

    init?(
        item: AttentionItem
    ) {
        guard let target = item.workflowApprovalTarget else {
            return nil
        }

        self.target = target
        sourceItem = item
        title = item.title
        subtitle = item.repository
    }

    init?(
        update: AttentionUpdate,
        sourceItem: AttentionItem
    ) {
        guard let target = update.workflowApprovalTarget else {
            return nil
        }

        self.target = target
        self.sourceItem = sourceItem
        title = update.title
        subtitle = sourceItem.title
    }

    init?(
        workflow: PullRequestPostMergeWorkflow,
        sourceItem: AttentionItem
    ) {
        guard let target = workflow.workflowApprovalTarget else {
            return nil
        }

        self.target = target
        self.sourceItem = sourceItem
        title = workflow.title
        subtitle = sourceItem.title
    }
}

struct WorkflowPendingDeploymentReviewSheet: View {
    let model: AppModel
    let request: WorkflowApprovalSheetRequest
    let onOpenGitHub: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var review: WorkflowPendingDeploymentReview?
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var submissionErrorMessage: String?
    @State private var isSubmitting = false
    @State private var selectedEnvironmentIDs = Set<Int>()
    @State private var comment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review Pending Deployments")
                    .font(.title3.weight(.semibold))

                Text(request.title)
                    .font(.headline)

                if let subtitle = request.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                if isLoading {
                    DetailCard {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)

                            Text("Loading pending environments...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let loadErrorMessage {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(loadErrorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button("Retry") {
                                    Task {
                                        await loadReview()
                                    }
                                }
                                .appInteractiveHover()

                                Button("Open on GitHub") {
                                    onOpenGitHub(request.target.url)
                                }
                                .appLinkHover()
                            }
                        }
                    }
                } else if let review {
                    content(for: review)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .task(id: request.id) {
            await loadReview()
        }
    }

    @ViewBuilder
    private func content(for review: WorkflowPendingDeploymentReview) -> some View {
        if review.environments.isEmpty {
            DetailCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This workflow run no longer has pending deployments.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Open on GitHub") {
                        onOpenGitHub(request.target.url)
                    }
                    .appLinkHover()
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                DetailCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(review.environments) { environment in
                            Toggle(isOn: selectionBinding(for: environment)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(environment.name)
                                        .font(.subheadline.weight(.semibold))

                                    if let reviewerSummary = environment.reviewerSummary {
                                        Text(reviewerSummary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if !environment.canApprove {
                                        Text("You can no longer approve this environment.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(!environment.canApprove || isSubmitting)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Comment")
                        .font(.subheadline.weight(.semibold))

                    ZStack(alignment: .topLeading) {
                        if comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Optional comment")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 6)
                        }

                        TextEditor(text: $comment)
                            .font(.body)
                            .frame(minHeight: 96)
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    )
                }

                if let submissionErrorMessage {
                    Text(submissionErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSubmitting)

                    Button("Open on GitHub") {
                        onOpenGitHub(request.target.url)
                    }
                    .appLinkHover()
                    .disabled(isSubmitting)

                    Spacer()

                    Button("Reject") {
                        submit(.rejected)
                    }
                    .disabled(!isSubmissionEnabled)
                    .appInteractiveHover()

                    Button {
                        submit(.approved)
                    } label: {
                        if isSubmitting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Submitting...")
                            }
                        } else {
                            Text("Approve and Deploy")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!isSubmissionEnabled)
                    .appInteractiveHover()
                }
            }
        }
    }

    private var isSubmissionEnabled: Bool {
        !selectedEnvironmentIDs.isEmpty && !isSubmitting
    }

    private func selectionBinding(
        for environment: WorkflowPendingEnvironment
    ) -> Binding<Bool> {
        Binding(
            get: {
                selectedEnvironmentIDs.contains(environment.id)
            },
            set: { isSelected in
                if isSelected {
                    selectedEnvironmentIDs.insert(environment.id)
                } else {
                    selectedEnvironmentIDs.remove(environment.id)
                }
            }
        )
    }

    private func loadReview() async {
        isLoading = true
        loadErrorMessage = nil

        do {
            let review = try await model.fetchPendingDeploymentReview(for: request.target)
            self.review = review
            selectedEnvironmentIDs = []
        } catch {
            loadErrorMessage = userFacingErrorMessage(for: error)
        }

        isLoading = false
    }

    private func submit(_ decision: WorkflowPendingDeploymentDecision) {
        guard !selectedEnvironmentIDs.isEmpty else {
            return
        }

        isSubmitting = true
        submissionErrorMessage = nil

        Task {
            do {
                try await model.reviewPendingDeployments(
                    for: request.target,
                    environmentIDs: selectedEnvironmentIDs.sorted(),
                    decision: decision,
                    comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceItem: request.sourceItem
                )
                dismiss()
            } catch {
                submissionErrorMessage = userFacingErrorMessage(for: error)
            }

            isSubmitting = false
        }
    }

    private func userFacingErrorMessage(
        for error: Error
    ) -> String {
        if let clientError = error as? GitHubClientError {
            switch clientError {
            case let .api(statusCode, message):
                return "GitHub API error \(statusCode): \(message)"
            default:
                return clientError.localizedDescription
            }
        }

        return error.localizedDescription
    }
}

private func color(for accent: PullRequestFocusEntryAccent) -> Color {
    switch accent {
    case .neutral:
        return .secondary
    case .warning:
        return .orange
    case .failure:
        return .red
    case .success:
        return .green
    case .resolved:
        return .mint
    case .change:
        return .teal
    }
}

private struct PullRequestFocusEntryRow: View {
    let entry: PullRequestFocusEntry
    let referenceDate: Date
    let onOpenURL: (URL) -> Void

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if let metadata = entry.metadata, !metadata.isEmpty {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let timestamp = entry.timestamp {
                        if entry.metadata != nil {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Text(relativeFormatter.localizedString(for: timestamp, relativeTo: referenceDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(absoluteFormatter.string(from: timestamp))
                    }
                }
            }

            Spacer(minLength: 12)

            if let url = entry.url {
                Button("Open") {
                    onOpenURL(url)
                }
                .buttonStyle(.link)
                .appInteractiveHover(scale: 0.992, opacity: 0.99)
            }
        }
    }

    private var accentColor: Color {
        color(for: entry.accent)
    }
}

private struct PullRequestPostMergeWorkflowRow: View {
    let workflow: PullRequestPostMergeWorkflow
    let sourceItem: AttentionItem
    let referenceDate: Date
    let onOpenURL: (URL) -> Void
    let onPresentWorkflowApproval: (WorkflowApprovalSheetRequest) -> Void

    private static let relativeFormatter = RelativeDateTimeFormatter()

    var body: some View {
        Button {
            if let workflowApprovalRequest = WorkflowApprovalSheetRequest(
                workflow: workflow,
                sourceItem: sourceItem
            ) {
                onPresentWorkflowApproval(workflowApprovalRequest)
            } else {
                onOpenURL(workflow.url)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: workflow.status.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color(for: workflow.status.accent))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(color(for: workflow.status.accent).opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(workflow.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: workflow.workflowApprovalTarget == nil ? "arrow.up.right.square" : "hand.raised")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appInteractiveHover(backgroundOpacity: 0.06, cornerRadius: 10)
        .help(
            workflow.workflowApprovalTarget == nil
                ? "Open workflow run on GitHub"
                : "Review pending deployments"
        )
    }

    private var statusLine: String {
        if let timestamp = workflow.timestamp {
            return workflow.status.label + " · " +
                Self.relativeFormatter.localizedString(for: timestamp, relativeTo: referenceDate)
        }

        return workflow.status.label
    }
}

private struct EventBadge: View {
    let type: AttentionItemType
    let secondaryType: AttentionItemType?
    var size: CGFloat = 24

    var body: some View {
        let helpText = AttentionItemType.badgeHelpText(primary: type, secondary: secondaryType)

        RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
            .fill(type.badgeBackground)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: type.iconName)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(type.badgeForeground)
            }
            .overlay(alignment: .bottomTrailing) {
                if let secondaryType {
                    Circle()
                        .fill(Color(NSColor.windowBackgroundColor))
                        .frame(width: size * 0.52, height: size * 0.52)
                        .overlay {
                            Circle()
                                .fill(secondaryType.badgeBackground)
                            Image(systemName: compactSecondaryIconName(for: secondaryType))
                                .font(.system(size: size * 0.2, weight: .bold))
                                .foregroundStyle(secondaryType.badgeForeground)
                        }
                        .offset(x: size * 0.12, y: size * 0.12)
                }
            }
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private func compactSecondaryIconName(for type: AttentionItemType) -> String {
        switch type {
        case .workflowApprovalRequired:
            return "hand.raised.fill"
        case .workflowRunning:
            return "clock.fill"
        case .workflowSucceeded:
            return "checkmark"
        case .workflowFailed:
            return "xmark"
        default:
            return type.iconName
        }
    }
}

private struct AttentionTypePill: View {
    let type: AttentionItemType
    let titleOverride: String?

    init(type: AttentionItemType, titleOverride: String? = nil) {
        self.type = type
        self.titleOverride = titleOverride
    }

    var body: some View {
        Label(titleOverride ?? type.accessibilityLabel, systemImage: type.iconName)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(type.badgeBackground)
            )
            .foregroundStyle(type.badgeForeground)
    }
}

private struct RepositoryMetadataView: View {
    let repository: String
    let repositoryURL: URL?
    let onOpenURL: (URL) -> Void

    var body: some View {
        Group {
            if let repositoryURL {
                Button {
                    onOpenURL(repositoryURL)
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        Text(repository)
                            .font(.subheadline)
                            .lineLimit(1)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appLinkHover()
                .help("Open repository on GitHub")
            } else {
                Text(repository)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct GitHubLabelChip: View {
    let label: GitHubLabel
    let actionURL: URL?
    let onOpenURL: (URL) -> Void
    let compact: Bool

    init(
        label: GitHubLabel,
        actionURL: URL? = nil,
        onOpenURL: @escaping (URL) -> Void = { _ in },
        compact: Bool = false
    ) {
        self.label = label
        self.actionURL = actionURL
        self.onOpenURL = onOpenURL
        self.compact = compact
    }

    private var palette: GitHubLabelPalette {
        GitHubLabelPalette(colorHex: label.colorHex)
    }

    var body: some View {
        Group {
            if let actionURL {
                Button {
                    onOpenURL(actionURL)
                } label: {
                    chipBody
                }
                .buttonStyle(.plain)
                .appLinkHover()
                .help(helpText)
            } else {
                chipBody
                    .help(helpText)
            }
        }
    }

    private var chipBody: some View {
        Text(label.name)
            .font(compact ? .caption2.weight(.medium) : .caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 2 : 6)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.fill)
            )
            .foregroundStyle(palette.text)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(palette.stroke, lineWidth: 1)
            )
    }

    private var helpText: String {
        if actionURL != nil {
            return label.description.map {
                "\($0)\nSearch this label on GitHub"
            } ?? "Search this label on GitHub"
        }

        return label.description ?? label.name
    }
}

private struct MetadataWrapLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let arrangement = arrange(subviews: subviews, in: proposal.width)
        return arrangement.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(subviews: subviews, in: bounds.width)

        for item in arrangement.items {
            let point = CGPoint(
                x: bounds.minX + item.frame.minX,
                y: bounds.minY + item.frame.minY
            )
            subviews[item.index].place(
                at: point,
                proposal: ProposedViewSize(item.frame.size)
            )
        }
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat?) -> MetadataWrapArrangement {
        let availableWidth = maxWidth ?? .greatestFiniteMagnitude
        var lines = [MetadataWrapLine]()
        var currentLineItems = [MetadataWrapLineItem]()
        var currentLineWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var cursorX: CGFloat = 0
        var contentWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let requiresNewLine = cursorX > 0 &&
                cursorX + size.width > availableWidth

            if requiresNewLine {
                lines.append(
                    MetadataWrapLine(
                        items: currentLineItems,
                        width: currentLineWidth,
                        height: currentLineHeight
                    )
                )
                currentLineItems = []
                currentLineWidth = 0
                currentLineHeight = 0
                cursorX = 0
            }

            currentLineItems.append(
                MetadataWrapLineItem(
                    index: index,
                    size: size,
                    minX: cursorX
                )
            )
            currentLineWidth = max(currentLineWidth, cursorX + size.width)
            currentLineHeight = max(currentLineHeight, size.height)
            cursorX += size.width + horizontalSpacing
        }

        if !currentLineItems.isEmpty {
            lines.append(
                MetadataWrapLine(
                    items: currentLineItems,
                    width: currentLineWidth,
                    height: currentLineHeight
                )
            )
        }

        var items = [MetadataWrapItem]()
        var cursorY: CGFloat = 0

        for line in lines {
            contentWidth = max(contentWidth, line.width)

            for item in line.items {
                let frame = CGRect(
                    x: item.minX,
                    y: cursorY + (line.height - item.size.height) / 2,
                    width: item.size.width,
                    height: item.size.height
                )
                items.append(MetadataWrapItem(index: item.index, frame: frame))
            }

            cursorY += line.height + verticalSpacing
        }

        let contentHeight = lines.isEmpty ? 0 : cursorY - verticalSpacing
        return MetadataWrapArrangement(
            items: items,
            size: CGSize(width: contentWidth, height: contentHeight)
        )
    }
}

private struct MetadataWrapArrangement {
    let items: [MetadataWrapItem]
    let size: CGSize
}

private struct MetadataWrapItem {
    let index: Int
    let frame: CGRect
}

private struct MetadataWrapLine {
    let items: [MetadataWrapLineItem]
    let width: CGFloat
    let height: CGFloat
}

private struct MetadataWrapLineItem {
    let index: Int
    let size: CGSize
    let minX: CGFloat
}

private struct SidebarOverflowChip: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
            .foregroundStyle(.secondary)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .help("\(count) more labels")
    }
}

private struct GitHubLabelPalette {
    let fill: Color
    let stroke: Color
    let text: Color

    init(colorHex: String) {
        guard let components = GitHubLabelColorComponents(hex: colorHex) else {
            fill = Color.secondary.opacity(0.12)
            stroke = Color.secondary.opacity(0.2)
            text = .primary
            return
        }

        let base = components.color
        if components.luminance > 0.72 {
            fill = base.opacity(0.3)
            stroke = base.opacity(0.68)
            text = Color.primary.opacity(0.9)
        } else {
            fill = base.opacity(0.18)
            stroke = base.opacity(0.3)
            text = base
        }
    }
}

private struct GitHubLabelColorComponents {
    let red: Double
    let green: Double
    let blue: Double

    init?(hex: String) {
        let normalized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }

        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var luminance: Double {
        let red = linearized(red)
        let green = linearized(green)
        let blue = linearized(blue)

        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func linearized(_ component: Double) -> Double {
        if component <= 0.03928 {
            return component / 12.92
        }

        return pow((component + 0.055) / 1.055, 2.4)
    }
}

private struct AttentionActorChip: View {
    let actor: AttentionActor
    let viewerLogin: String?

    var body: some View {
        HStack(spacing: 6) {
            DetailActorAvatar(actor: actor, size: 16)
            Text(presentation.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if presentation.showsBotBadge {
                BotAccountChip(login: actor.login, compact: true)
            }
        }
    }

    private var presentation: AttentionViewerPresentationPolicy.ActorPresentation {
        AttentionViewerPresentationPolicy.actorPresentation(
            for: actor,
            viewerLogin: viewerLogin
        )
    }
}

private struct DetailActorAvatar: View {
    let actor: AttentionActor
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let avatarURL = actor.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(.secondary)
            }
    }
}

private extension AttentionItemType {
    var badgeForeground: Color {
        switch self {
        case .assignedPullRequest:
            return .blue
        case .authoredPullRequest:
            return .teal
        case .reviewedPullRequest:
            return .indigo
        case .commentedPullRequest:
            return .cyan
        case .readyToMerge:
            return .green
        case .pullRequestMergeConflicts:
            return .orange
        case .pullRequestFailedChecks:
            return .red
        case .assignedIssue:
            return .orange
        case .authoredIssue:
            return .brown
        case .commentedIssue:
            return .secondary
        case .comment, .reviewComment:
            return .secondary
        case .mention:
            return .purple
        case .teamMention:
            return .pink
        case .newCommitsAfterComment:
            return .teal
        case .newCommitsAfterReview:
            return .cyan
        case .reviewRequested:
            return .indigo
        case .teamReviewRequested:
            return .mint
        case .reviewApproved:
            return .green
        case .reviewChangesRequested:
            return .orange
        case .pullRequestStateChanged:
            return .brown
        case .ciActivity:
            return .teal
        case .workflowRunning:
            return .blue
        case .workflowSucceeded:
            return .green
        case .workflowFailed:
            return .red
        case .workflowApprovalRequired:
            return .orange
        }
    }

    var badgeBackground: Color {
        switch self {
        case .assignedPullRequest:
            return .blue.opacity(0.14)
        case .authoredPullRequest:
            return .teal.opacity(0.14)
        case .reviewedPullRequest:
            return .indigo.opacity(0.14)
        case .commentedPullRequest:
            return .cyan.opacity(0.16)
        case .readyToMerge:
            return .green.opacity(0.16)
        case .pullRequestMergeConflicts:
            return .orange.opacity(0.16)
        case .pullRequestFailedChecks:
            return .red.opacity(0.14)
        case .assignedIssue:
            return .orange.opacity(0.16)
        case .authoredIssue:
            return .brown.opacity(0.16)
        case .commentedIssue:
            return .secondary.opacity(0.12)
        case .comment, .reviewComment:
            return .secondary.opacity(0.12)
        case .mention:
            return .purple.opacity(0.14)
        case .teamMention:
            return .pink.opacity(0.14)
        case .newCommitsAfterComment:
            return .teal.opacity(0.14)
        case .newCommitsAfterReview:
            return .cyan.opacity(0.16)
        case .reviewRequested:
            return .indigo.opacity(0.14)
        case .teamReviewRequested:
            return .mint.opacity(0.18)
        case .reviewApproved:
            return .green.opacity(0.14)
        case .reviewChangesRequested:
            return .orange.opacity(0.14)
        case .pullRequestStateChanged:
            return .brown.opacity(0.14)
        case .ciActivity:
            return .teal.opacity(0.14)
        case .workflowRunning:
            return .blue.opacity(0.14)
        case .workflowSucceeded:
            return .green.opacity(0.14)
        case .workflowFailed:
            return .red.opacity(0.14)
        case .workflowApprovalRequired:
            return .orange.opacity(0.14)
        }
    }
}

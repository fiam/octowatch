import AppKit
import SwiftUI

struct AttentionWindowView: View {
    private enum StreamFilter: String, CaseIterable, Identifiable {
        case all
        case notifications
        case pullRequests
        case issues

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .notifications:
                return AttentionStream.notifications.title
            case .pullRequests:
                return AttentionStream.pullRequests.title
            case .issues:
                return AttentionStream.issues.title
            }
        }

        var iconName: String {
            switch self {
            case .all:
                return "square.stack.3d.up"
            case .notifications:
                return AttentionStream.notifications.iconName
            case .pullRequests:
                return AttentionStream.pullRequests.iconName
            case .issues:
                return AttentionStream.issues.iconName
            }
        }

        var stream: AttentionStream? {
            switch self {
            case .all:
                return nil
            case .notifications:
                return .notifications
            case .pullRequests:
                return .pullRequests
            case .issues:
                return .issues
            }
        }
    }

    private enum ListFilter: String, CaseIterable, Identifiable {
        case all
        case unread

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .unread:
                return "Unread"
            }
        }
    }

    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    @State private var selectedItemIDs = Set<AttentionItem.ID>()
    @State private var streamFilter: StreamFilter = .all
    @State private var listFilter: ListFilter = .all
    @State private var autoMarkReadTask: Task<Void, Never>?
    @State private var pullRequestFocusState: PullRequestFocusLoadState = .idle
    @State private var reviewMergeState: PullRequestReviewMergeState = .idle

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack(alignment: .bottomTrailing) {
                if showsInitialLoadingState {
                    loadingView
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else {
                    NavigationSplitView {
                        sidebar(relativeTo: context.date)
                    } detail: {
                        detailPane(relativeTo: context.date)
                    }
                    .transition(.opacity)
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
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 620)
        .onAppear {
            syncSelection()
            updateWatchedPullRequestSelection()
        }
        .onDisappear {
            cancelAutoMarkReadTask()
            model.setWatchedPullRequest(nil)
        }
        .onChange(of: model.attentionItems) { _, _ in
            syncSelection()
        }
        .onChange(of: streamFilter) { _, _ in
            syncSelection()
        }
        .onChange(of: listFilter) { _, _ in
            syncSelection()
        }
        .onChange(of: model.autoMarkReadSetting) { _, _ in
            if autoMarkReadTask != nil {
                armAutoMarkReadForCurrentSelection()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsInitialLoadingState)
        .animation(.easeInOut(duration: 0.18), value: model.ignoreUndoState?.id)
        .task(id: pullRequestFocusTaskID) {
            await loadPullRequestFocusForSelection()
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
                            await model.forceRefresh(item: item)
                        }
                    } label: {
                        Label("Refresh Item", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
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

    private var showsInitialLoadingState: Bool {
        model.isResolvingInitialContent
    }

    private var streamItems: [AttentionItem] {
        guard let stream = streamFilter.stream else {
            return model.combinedAttentionItems
        }

        return model.attentionItems.filter { $0.stream == stream }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Refreshing inbox…")
                .font(.title3.weight(.semibold))

            Text("Fetching the latest GitHub activity.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var displayedItems: [AttentionItem] {
        switch listFilter {
        case .all:
            return streamItems
        case .unread:
            return streamItems.filter(\.isUnread)
        }
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
                if !model.hasToken {
                    connectionRequiredView
                } else if displayedItems.isEmpty {
                    emptyStateView
                } else {
                    List(displayedItems, selection: selectionBinding) { item in
                        AttentionSidebarRow(
                            item: item,
                            viewerLogin: model.viewerLogin,
                            relativeTimestamp: relativeFormatter.localizedString(
                                for: item.timestamp,
                            relativeTo: referenceDate
                            )
                        )
                        .contentShape(Rectangle())
                        .contextMenu {
                            selectionContextMenu(for: contextMenuItems(for: item))
                        }
                        .tag(item.id)
                    }
                    .accessibilityIdentifier("inbox-list")
                    .listStyle(.sidebar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 360)
    }

    private func sidebarHeader(relativeTo referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Inbox")
                    .font(.title2.weight(.semibold))

                Spacer()

                unreadFilterButton

                Button(action: model.refreshNow) {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(model.isRefreshing ? 0 : 1)

                        if model.isRefreshing && !showsInitialLoadingState {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: 18, height: 18)
                }
                .disabled(model.isRefreshing)
                .buttonStyle(.borderless)
                .appInteractiveHover(backgroundOpacity: 0.08, cornerRadius: 8)
                .help("Refresh")
            }

            streamFilterRow

            Text("\(displayedItems.count) items · \(streamItems.filter(\.isUnread).count) unread")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(model.relativeLastUpdated(relativeTo: referenceDate))
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.showsDebugRateLimitDetails, !model.rateLimitBuckets.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diagnostics")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let header = model.rateLimitDebugHeader(relativeTo: referenceDate) {
                        Text(header)
                            .font(.caption2)
                            .foregroundStyle(model.isRateLimitWarning ? .orange : .secondary)
                            .lineLimit(2)
                    }

                    ForEach(model.rateLimitBuckets, id: \.resourceKey) { bucket in
                        Text(model.rateLimitBucketSummary(for: bucket, relativeTo: referenceDate))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(bucket.isLow || bucket.isExhausted ? .orange : .secondary)
                            .lineLimit(2)
                    }
                }
            }

            if let lastError = model.lastError {
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

    private var unreadFilterButton: some View {
        Button {
            listFilter = listFilter == .unread ? .all : .unread
        } label: {
            HStack(spacing: 6) {
                Image(systemName: listFilter == .unread ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .imageScale(.medium)
                Text("Unread")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(listFilter == .unread ? .white : .primary)
            .background(
                Capsule(style: .continuous)
                    .fill(listFilter == .unread ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        listFilter == .unread
                            ? Color.accentColor.opacity(0.85)
                            : Color(nsColor: .separatorColor).opacity(0.45),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .appInteractiveHover(backgroundOpacity: listFilter == .unread ? 0 : 0.08, cornerRadius: 999)
        .help(listFilter == .unread ? "Show all items" : "Show unread items")
        .accessibilityLabel(listFilter == .unread ? "Showing unread items" : "Showing all items")
    }

    private var streamFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StreamFilter.allCases) { filter in
                    Button {
                        streamFilter = filter
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.iconName)
                                .imageScale(.small)

                            Text(filter.title)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(streamFilter == filter ? .white : .primary)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    streamFilter == filter
                                        ? Color.accentColor
                                        : Color(nsColor: .controlBackgroundColor)
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    streamFilter == filter
                                        ? Color.accentColor.opacity(0.85)
                                        : Color(nsColor: .separatorColor).opacity(0.45),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .appInteractiveHover(
                        backgroundOpacity: streamFilter == filter ? 0 : 0.08,
                        cornerRadius: 999
                    )
                    .accessibilityLabel("Show \(filter.title)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func detailPane(relativeTo referenceDate: Date) -> some View {
        Group {
            if !model.hasToken {
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
        let scopeName = streamFilter == .all ? "items" : streamFilter.title.lowercased()
        let title = listFilter == .unread
            ? "No unread \(scopeName)"
            : streamFilter == .all ? "Inbox is clear" : "No \(scopeName)"
        let description = listFilter == .unread
            ? "Everything in \(streamFilter == .all ? "the inbox" : "this stream") has been marked read."
            : streamFilter == .all
                ? "Octowatch is watching GitHub, but there is nothing actionable right now."
                : "Octowatch is watching GitHub, but there is nothing actionable in this stream right now."

        return ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle")
        } description: {
            Text(description)
        }
    }

    private var multipleSelectionView: some View {
        ContentUnavailableView {
            Label("\(selectionActionItems.count) Items Selected", systemImage: "checklist")
        } description: {
            Text("Use the toolbar or the right-click menu to open items, update their read state, or ignore them.")
        }
    }

    private func syncSelection() {
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
    }

    private func updateWatchedPullRequestSelection() {
        model.setWatchedPullRequest(selectedItem)
    }

    private func normalizeSelection(_ selection: Set<AttentionItem.ID>) -> Set<AttentionItem.ID> {
        let displayedItemIDs = Set(displayedItems.map(\.id))
        let normalizedSelection = selection.intersection(displayedItemIDs)

        if !normalizedSelection.isEmpty || displayedItems.isEmpty {
            return normalizedSelection
        }

        guard let firstItemID = displayedItems.first?.id else {
            return []
        }

        return [firstItemID]
    }

    private func openRelatedURL(_ url: URL, for item: AttentionItem) {
        cancelAutoMarkReadTask()
        model.markItemAsRead(item)
        openURL(url)
    }

    private func openSelection(_ items: [AttentionItem]) {
        cancelAutoMarkReadTask()
        model.markItemsAsRead(items)

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

    private func contextMenuItems(for item: AttentionItem) -> [AttentionItem] {
        if selectedItemIDs.contains(item.id) {
            return selectionActionItems
        }

        return [item]
    }

    @ViewBuilder
    private func selectionContextMenu(for items: [AttentionItem]) -> some View {
        Button {
            openSelection(items)
        } label: {
            Label("Open", systemImage: "safari")
        }

        Button {
            markSelectionAsRead(items)
        } label: {
            Label("Mark as Read", systemImage: "circle")
        }
        .disabled(!items.contains(where: \.isUnread))

        Button {
            markSelectionAsUnread(items)
        } label: {
            Label("Mark as Unread", systemImage: "circle.fill")
        }
        .disabled(!items.contains(where: { !$0.isUnread }))

        Divider()

        Button {
            ignoreSelection(items)
        } label: {
            Label("Ignore", systemImage: "eye.slash")
        }
    }

    private func armAutoMarkReadForCurrentSelection() {
        cancelAutoMarkReadTask()

        guard let item = selectedItem,
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

    private let maximumDisplayedLabels = 2

    private var displayedLabels: [GitHubLabel] {
        Array(item.labels.prefix(maximumDisplayedLabels))
    }

    private var hiddenLabelCount: Int {
        max(0, item.labels.count - displayedLabels.count)
    }

    private var sidebarContextSubtitle: String? {
        let trimmedSubtitle = item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubtitle.isEmpty else {
            return nil
        }

        guard let repository = item.repository else {
            return trimmedSubtitle
        }

        let segments = trimmedSubtitle
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != repository }
        let collapsed = segments.joined(separator: " · ")

        guard !collapsed.isEmpty else {
            return nil
        }

        return AttentionViewerPresentationPolicy.personalizing(
            collapsed,
            viewerLogin: viewerLogin
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .opacity(item.isUnread ? 1 : 0)
                .padding(.top, 6)
                .frame(width: 10)

            EventBadge(type: item.type, secondaryType: item.secondaryIndicatorType)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier("sidebar-item-title-\(item.id)")
                    .accessibilityValue(item.isUnread ? "unread" : "read")

                if let sidebarContextSubtitle {
                    Text(sidebarContextSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if item.repository != nil || !displayedLabels.isEmpty || hiddenLabelCount > 0 {
                    MetadataWrapLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                        if let repository = item.repository {
                            Text(repository)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        ForEach(displayedLabels) { label in
                            GitHubLabelChip(
                                label: label,
                                actionURL: nil,
                                onOpenURL: { _ in },
                                compact: true
                            )
                        }

                        if hiddenLabelCount > 0 {
                            SidebarOverflowChip(count: hiddenLabelCount)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if let actor = item.actor {
                        AttentionActorChip(actor: actor, viewerLogin: viewerLogin)
                    }

                    Text(relativeTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
                                    viewerLogin: viewerLogin,
                                    referenceDate: referenceDate,
                                    onOpenURL: onOpenURL
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
                referenceDate: referenceDate,
                reviewMergeState: reviewMergeState,
                onOpenURL: onOpenURL,
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
    let viewerLogin: String?
    let referenceDate: Date
    let onOpenURL: (URL) -> Void

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

                if let detail = renderedDetail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(Self.relativeFormatter.localizedString(for: update.timestamp, relativeTo: referenceDate))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            if let url = update.url {
                Button("Open") {
                    onOpenURL(url)
                }
                .buttonStyle(.link)
                .appLinkHover()
            }
        }
    }

    private var renderedDetail: String? {
        AttentionViewerPresentationPolicy.updateDetailText(
            actor: update.actor,
            detail: update.detail,
            viewerLogin: viewerLogin
        )
    }
}

private struct PullRequestFocusView: View {
    let focus: PullRequestFocus
    let referenceDate: Date
    let reviewMergeState: PullRequestReviewMergeState
    let onOpenURL: (URL) -> Void
    let onPerformReviewMerge: (PullRequestMergeMethod?) -> Void
    let onSelectMergeMethod: (PullRequestMergeMethod) -> Void

    @State private var selectedMergeMethod: PullRequestMergeMethod?

    init(
        focus: PullRequestFocus,
        referenceDate: Date,
        reviewMergeState: PullRequestReviewMergeState,
        onOpenURL: @escaping (URL) -> Void,
        onPerformReviewMerge: @escaping (PullRequestMergeMethod?) -> Void,
        onSelectMergeMethod: @escaping (PullRequestMergeMethod) -> Void
    ) {
        self.focus = focus
        self.referenceDate = referenceDate
        self.reviewMergeState = reviewMergeState
        self.onOpenURL = onOpenURL
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !focus.contextBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(focus.contextBadges) { badge in
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
                                    referenceDate: referenceDate,
                                    onOpenURL: onOpenURL
                                )
                            }
                        }

                        if let footnote = postMergeWorkflowPreview.footnote {
                            Text(footnote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
            Button(AttentionViewerPresentationPolicy.actorLabel(for: actor, viewerLogin: viewerLogin)) {
                onOpenURL(actor.profileURL)
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.plain)
            .appLinkHover()
            .foregroundStyle(actor.isBotAccount ? Color.primary : Color.accentColor)

            if actor.isBotAccount {
                BotAccountChip(login: actor.login)
            }
        }
    }
}

private struct BotAccountChip: View {
    let login: String

    var body: some View {
        Image(systemName: "cpu")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )
            .help("\(login) is a bot account")
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
    let referenceDate: Date
    let onOpenURL: (URL) -> Void

    private static let relativeFormatter = RelativeDateTimeFormatter()

    var body: some View {
        Button {
            onOpenURL(workflow.url)
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

                Image(systemName: "arrow.up.right.square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appLinkHover()
        .help("Open workflow run on GitHub")
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
            Text(AttentionViewerPresentationPolicy.actorLabel(for: actor, viewerLogin: viewerLogin))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

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

    @State private var selectedItemID: AttentionItem.ID?
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

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack(alignment: .bottom) {
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
                        ignoredItem: ignoreUndoState.subject,
                        onUndo: model.undoRecentIgnore,
                        onDismiss: model.dismissIgnoreUndo
                    )
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            if let selectedItem, model.hasToken {
                ToolbarItemGroup {
                    Button {
                        openSelectedItem(selectedItem)
                    } label: {
                        Label("Open", systemImage: "safari")
                    }
                    .appInteractiveHover()
                    .help("Open on GitHub")

                    Button {
                        toggleReadState(for: selectedItem)
                    } label: {
                        Label(
                            selectedItem.isUnread ? "Mark Read" : "Mark Unread",
                            systemImage: selectedItem.isUnread ? "circle" : "circle.fill"
                        )
                    }
                    .appInteractiveHover()
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .accessibilityIdentifier("item-toggle-read-state")
                    .accessibilityLabel(selectedItem.isUnread ? "Mark Read" : "Mark Unread")
                    .help(selectedItem.isUnread ? "Mark Read" : "Mark Unread")

                    Button {
                        model.ignore(selectedItem)
                    } label: {
                        Label("Ignore", systemImage: "eye.slash")
                    }
                    .appInteractiveHover()
                    .help(selectedItem.ignoreActionTitle)
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

    private var selectedItem: AttentionItem? {
        guard let selectedItemID else {
            return displayedItems.first
        }

        return displayedItems.first(where: { $0.id == selectedItemID })
    }

    private var pullRequestFocusTaskID: String? {
        guard let item = selectedItem, item.pullRequestReference != nil else {
            return nil
        }

        return "\(item.ignoreKey)#\(item.timestamp.timeIntervalSince1970)#\(model.lastUpdated?.timeIntervalSince1970 ?? 0)"
            + "#\(model.pullRequestWatchRevision)"
    }

    private var selectionBinding: Binding<AttentionItem.ID?> {
        Binding(
            get: { selectedItemID },
            set: { newValue in
                let selectionChanged = selectedItemID != newValue
                selectedItemID = newValue

                if selectionChanged {
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
                            relativeTimestamp: relativeFormatter.localizedString(
                                for: item.timestamp,
                            relativeTo: referenceDate
                            )
                        )
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

            if let rateLimitSummary = model.rateLimitSummary(relativeTo: referenceDate) {
                Text(rateLimitSummary)
                    .font(.caption)
                    .foregroundStyle(model.isRateLimitWarning ? .orange : .secondary)
                    .lineLimit(2)
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
            } else if let item = selectedItem {
                AttentionDetailView(
                    item: item,
                    absoluteTimestamp: timestampFormatter.string(from: item.timestamp),
                    relativeTimestamp: relativeFormatter.localizedString(
                        for: item.timestamp,
                        relativeTo: referenceDate
                    ),
                    referenceDate: referenceDate,
                    pullRequestFocusState: pullRequestFocusState,
                    reviewMergeState: reviewMergeState,
                    onOpenURL: { url in
                        openRelatedURL(url, for: item)
                    },
                    onPerformReviewMerge: {
                        Task {
                            await performReviewMergeForSelection()
                        }
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

    private func syncSelection() {
        let previousSelectionID = selectedItemID

        if let currentSelectionID = selectedItemID,
            displayedItems.contains(where: { $0.id == currentSelectionID }) {
            selectedItemID = currentSelectionID
        } else {
            selectedItemID = displayedItems.first?.id
        }

        if previousSelectionID != selectedItemID {
            cancelAutoMarkReadTask()
            pullRequestFocusState = .idle
            reviewMergeState = .idle
        }

        updateWatchedPullRequestSelection()
    }

    private func updateWatchedPullRequestSelection() {
        model.setWatchedPullRequest(selectedItem)
    }

    private func openSelectedItem(_ item: AttentionItem) {
        openRelatedURL(item.url, for: item)
    }

    private func openRelatedURL(_ url: URL, for item: AttentionItem) {
        cancelAutoMarkReadTask()
        model.markItemAsRead(item)
        openURL(url)
    }

    private func toggleReadState(for item: AttentionItem) {
        cancelAutoMarkReadTask()
        model.toggleReadState(for: item)
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

    private func performReviewMergeForSelection() async {
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
                mergeMethod: reviewMergeAction.mergeMethod
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
    let relativeTimestamp: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .opacity(item.isUnread ? 1 : 0)
                .padding(.top, 6)
                .frame(width: 10)

            EventBadge(type: item.type)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier("sidebar-item-title-\(item.id)")
                    .accessibilityValue(item.isUnread ? "unread" : "read")

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let actor = item.actor {
                        AttentionActorChip(actor: actor)
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
    let absoluteTimestamp: String
    let relativeTimestamp: String
    let referenceDate: Date
    let pullRequestFocusState: PullRequestFocusLoadState
    let reviewMergeState: PullRequestReviewMergeState
    let onOpenURL: (URL) -> Void
    let onPerformReviewMerge: () -> Void
    let onRetryPullRequestFocus: () -> Void

    private var visibleEvidence: [AttentionEvidence] {
        item.detail.evidence.filter { evidence in
            evidence.id != "actor" && evidence.id != "repository"
        }
    }

    private var loadedPullRequestFocus: PullRequestFocus? {
        guard case let .loaded(focus) = pullRequestFocusState else {
            return nil
        }

        return focus
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 18) {
                        EventBadge(type: item.type, size: 40)

                        DetailTitleLinkButton(
                            title: item.title,
                            action: {
                                onOpenURL(item.url)
                            }
                        )
                    }

                    if let repository = item.repository {
                        if let repositoryURL = item.repositoryURL {
                            Button {
                                onOpenURL(repositoryURL)
                            } label: {
                                HStack(alignment: .center, spacing: 6) {
                                    Text(repository)
                                        .font(.subheadline)

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
                                    onOpenURL: onOpenURL
                                )
                            }

                            Text("·")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)

                            Text(relativeTimestamp)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .help(absoluteTimestamp)
                        }
                    } else {
                        HStack(alignment: .center, spacing: 10) {
                            AttentionTypePill(type: item.type, titleOverride: headerPillTitleOverride)

                            if let actor = item.actor {
                                Text(item.type == .readyToMerge ? "approved by" : "by")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                DetailActorAvatar(actor: actor, size: 20)

                                ActorLinkLabel(
                                    actor: actor,
                                    onOpenURL: onOpenURL
                                )
                            }

                            Text("·")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)

                            Text(relativeTimestamp)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .help(absoluteTimestamp)
                        }
                    }
                }

                if item.pullRequestReference == nil && !visibleEvidence.isEmpty {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(visibleEvidence) { evidence in
                                DetailEvidenceRow(
                                    evidence: evidence,
                                    onOpenURL: onOpenURL
                                )
                            }
                        }
                    }
                }

                pullRequestFocusContent
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
                onPerformReviewMerge: onPerformReviewMerge
            )
        }
    }
}

private struct IgnoreUndoBanner: View {
    let ignoredItem: IgnoredAttentionSubject
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "eye.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Ignored \(ignoredItem.title)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("Undo is available for a few seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Undo", action: onUndo)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .appInteractiveHover()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .appInteractiveHover(backgroundOpacity: 0.08, cornerRadius: 999)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
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
                    Text(detail)
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

private struct PullRequestFocusView: View {
    let focus: PullRequestFocus
    let referenceDate: Date
    let reviewMergeState: PullRequestReviewMergeState
    let onOpenURL: (URL) -> Void
    let onPerformReviewMerge: () -> Void

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
            reviewMergeAction.isEnabled
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
                            Button {
                                onPerformReviewMerge()
                            } label: {
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
                                        reviewMergeAction.title,
                                        systemImage: reviewMergeAction.outcome?.iconName
                                            ?? (reviewMergeAction.requiresApproval
                                                ? "checkmark.circle.badge.questionmark"
                                                : "checkmark.circle")
                                    )
                                }
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

            if let postMergeWorkflowPreview = focus.postMergeWorkflowPreview,
                focus.resolution == .open {
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

                        if postMergeWorkflowPreview.isBestEffort {
                            Text(postMergeWorkflowPreview.footnote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
        }
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
    let onOpenURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(fact.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DetailActorAvatar(actor: fact.actor, size: 20)

            ActorLinkLabel(
                actor: fact.actor,
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
    let onOpenURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(actor.login) {
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
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(workflow.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(Self.relativeFormatter.localizedString(for: workflow.lastRunAt, relativeTo: referenceDate))
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
}

private struct EventBadge: View {
    let type: AttentionItemType
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
            .fill(type.badgeBackground)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: type.iconName)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(type.badgeForeground)
            }
            .accessibilityLabel(type.accessibilityLabel)
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

private struct AttentionActorChip: View {
    let actor: AttentionActor

    var body: some View {
        HStack(spacing: 6) {
            DetailActorAvatar(actor: actor, size: 16)
            Text(actor.login)
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
        case .workflowFailed:
            return .red.opacity(0.14)
        case .workflowApprovalRequired:
            return .orange.opacity(0.14)
        }
    }
}

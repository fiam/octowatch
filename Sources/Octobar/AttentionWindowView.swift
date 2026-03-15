import AppKit
import SwiftUI

struct AttentionWindowView: View {
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
    @State private var listFilter: ListFilter = .all
    @State private var autoMarkReadTask: Task<Void, Never>?

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
            ZStack {
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
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 620)
        .onAppear {
            syncSelection()
            updateAutoMarkReadSchedule()
        }
        .onDisappear {
            cancelAutoMarkReadTask()
        }
        .onChange(of: selectedItemID) { _, _ in
            updateAutoMarkReadSchedule()
        }
        .onChange(of: model.attentionItems) { _, _ in
            syncSelection()
            updateAutoMarkReadSchedule()
        }
        .onChange(of: listFilter) { _, _ in
            syncSelection()
            updateAutoMarkReadSchedule()
        }
        .onChange(of: model.autoMarkReadSetting) { _, _ in
            updateAutoMarkReadSchedule()
        }
        .animation(.easeInOut(duration: 0.18), value: showsInitialLoadingState)
        .toolbar {
            if let selectedItem, model.hasToken {
                ToolbarItemGroup {
                    Button {
                        openSelectedItem(selectedItem)
                    } label: {
                        Label("Open", systemImage: "safari")
                    }
                    .help("Open on GitHub")

                    Button {
                        model.toggleReadState(for: selectedItem)
                    } label: {
                        Label(
                            selectedItem.isUnread ? "Mark Read" : "Mark Unread",
                            systemImage: selectedItem.isUnread ? "circle" : "circle.fill"
                        )
                    }
                    .help(selectedItem.isUnread ? "Mark Read" : "Mark Unread")

                    Button {
                        model.ignore(selectedItem)
                    } label: {
                        Label("Ignore", systemImage: "eye.slash")
                    }
                    .help(selectedItem.ignoreActionTitle)
                }
            }

            ToolbarItem {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    private var showsInitialLoadingState: Bool {
        model.isResolvingInitialContent
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
            return model.attentionItems
        case .unread:
            return model.attentionItems.filter(\.isUnread)
        }
    }

    private var selectedItem: AttentionItem? {
        guard let selectedItemID else {
            return displayedItems.first
        }

        return displayedItems.first(where: { $0.id == selectedItemID })
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
                    List(displayedItems, selection: $selectedItemID) { item in
                        AttentionSidebarRow(
                            item: item,
                            relativeTimestamp: relativeFormatter.localizedString(
                                for: item.timestamp,
                                relativeTo: referenceDate
                            )
                        )
                        .tag(item.id)
                    }
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
                .help("Refresh")
            }

            Text("\(displayedItems.count) items · \(model.unreadCount) unread")
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
        .help(listFilter == .unread ? "Show all items" : "Show unread items")
        .accessibilityLabel(listFilter == .unread ? "Showing unread items" : "Showing all items")
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
                    onOpenItem: {
                        openSelectedItem(item)
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
        }
    }

    private var emptyStateView: some View {
        let title = listFilter == .unread ? "No unread items" : "Inbox is clear"
        let description = listFilter == .unread
            ? "Everything in the inbox has been marked read."
            : "Octowatch is watching GitHub, but there is nothing actionable right now."

        return ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle")
        } description: {
            Text(description)
        }
    }

    private func syncSelection() {
        if let selectedItem, displayedItems.contains(where: { $0.id == selectedItem.id }) {
            selectedItemID = selectedItem.id
            return
        }

        selectedItemID = displayedItems.first?.id
    }

    private func openSelectedItem(_ item: AttentionItem) {
        model.markItemAsRead(item)
        openURL(item.url)
    }

    private func updateAutoMarkReadSchedule() {
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

    private func cancelAutoMarkReadTask() {
        autoMarkReadTask?.cancel()
        autoMarkReadTask = nil
    }
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
    let onOpenItem: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    EventBadge(type: item.type, size: 40)

                    DetailTitleLinkButton(
                        title: item.title,
                        action: onOpenItem
                    )

                    HStack(alignment: .center, spacing: 10) {
                        AttentionTypePill(type: item.type)

                        if let actor = item.actor {
                            Text("by")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            DetailActorAvatar(actor: actor, size: 20)

                            if actor.isBotAccount {
                                Text(actor.login)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                            } else {
                                Link(actor.login, destination: actor.profileURL)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                DetailCard(title: "Context") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Summary") {
                            Text(item.subtitle)
                                .multilineTextAlignment(.trailing)
                        }

                        LabeledContent("When") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(relativeTimestamp)
                                Text(absoluteTimestamp)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.body)
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

private struct DetailTitleLinkButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

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
        .help("Open on GitHub")
        .onHover(perform: updateHoverState)
        .onDisappear {
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private func updateHoverState(_ hovering: Bool) {
        guard hovering != isHovering else {
            return
        }

        isHovering = hovering

        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

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

    var body: some View {
        Label(type.accessibilityLabel, systemImage: type.iconName)
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
        case .comment, .reviewComment:
            return .secondary
        case .mention:
            return .purple
        case .reviewRequested:
            return .indigo
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
        case .comment, .reviewComment:
            return .secondary.opacity(0.12)
        case .mention:
            return .purple.opacity(0.14)
        case .reviewRequested:
            return .indigo.opacity(0.14)
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

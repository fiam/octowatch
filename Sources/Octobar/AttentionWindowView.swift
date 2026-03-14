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
        }
        .onChange(of: model.attentionItems) { _, _ in
            syncSelection()
        }
        .onChange(of: listFilter) { _, _ in
            syncSelection()
        }
        .animation(.easeInOut(duration: 0.18), value: showsInitialLoadingState)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Filter", selection: $listFilter) {
                    ForEach(ListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            ToolbarItem {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ToolbarItem {
                Button(action: model.refreshNow) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
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
                .safeAreaInset(edge: .top) {
                    sidebarHeader(relativeTo: referenceDate)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 360)
    }

    private func sidebarHeader(relativeTo referenceDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inbox")
                .font(.title2.weight(.semibold))

            Text("\(displayedItems.count) items · \(model.unreadCount) unread")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(model.relativeLastUpdated(relativeTo: referenceDate))
                .font(.caption)
                .foregroundStyle(.secondary)

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
                    onOpen: {
                        model.markItemAsRead(item)
                        openURL(item.url)
                    },
                    onToggleRead: {
                        model.toggleReadState(for: item)
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
}

private struct AttentionSidebarRow: View {
    let item: AttentionItem
    let relativeTimestamp: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EventBadge(type: item.type)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)

                    if item.isUnread {
                        Circle()
                            .fill(.blue)
                            .frame(width: 7, height: 7)
                    }
                }

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
    let onOpen: () -> Void
    let onToggleRead: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    EventBadge(type: item.type, size: 40)

                    Text(item.title)
                        .font(.largeTitle.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        AttentionTypePill(type: item.type)

                        if item.isUnread {
                            Text("Unread")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                    }
                }

                if let actor = item.actor {
                    DetailCard(title: "Triggered by") {
                        HStack(spacing: 12) {
                            DetailActorAvatar(actor: actor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(actor.login)
                                    .font(.headline)
                                Text(item.type.accessibilityLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
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

                HStack(spacing: 12) {
                    Button("Open on GitHub", action: onOpen)
                        .buttonStyle(.borderedProminent)

                    Button(item.isUnread ? "Mark Read" : "Mark Unread", action: onToggleRead)
                        .buttonStyle(.bordered)
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
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

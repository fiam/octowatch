import SwiftUI

struct MenuBarContentView: View {
    private enum LayoutMetrics {
        static let width: CGFloat = 360
        static let contentPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 10
        static let maxListHeight: CGFloat = 320
    }

    @ObservedObject var model: AppModel
    var onRenderedHeightChange: ((CGFloat) -> Void)? = nil
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @State private var inboxListContentHeight: CGFloat = 0

    var body: some View {
        content
            .frame(width: LayoutMetrics.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
        .onPreferenceChange(MenuBarContentHeightPreferenceKey.self) { height in
            guard height.isFinite, height > 0 else {
                return
            }

            onRenderedHeightChange?(height)
        }
        .onPreferenceChange(MenuBarListContentHeightPreferenceKey.self) { height in
            guard height.isFinite, height > 0 else {
                return
            }

            inboxListContentHeight = height
        }
        .onChange(of: inboxSectionLayoutSignature) { _, _ in
            inboxListContentHeight = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .performMainWindowOpen)) { _ in
            openWindow(id: AppSceneID.mainWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSettingsOpen)) { _ in
            openWindow(id: AppSceneID.settingsWindow)
        }
    }

    private var inboxSectionLayoutSignature: String {
        model.inboxSections
            .map { section in
                "\(section.name)#\(min(section.items.count, 10))"
            }
            .joined(separator: "|")
    }

    private var estimatedInboxListHeight: CGFloat {
        model.inboxSections.enumerated().reduce(CGFloat(0)) { partialHeight, element in
            let (index, section) = element
            let visibleItemCount = min(section.items.count, 10)
            let sectionTopPadding: CGFloat = index == 0 ? 0 : 8
            let sectionHeaderHeight: CGFloat = 18
            let itemRowHeight: CGFloat = 42
            let itemSpacing: CGFloat = 2
            let rowBlockHeight = CGFloat(visibleItemCount) * itemRowHeight
            let intraRowSpacing = CGFloat(max(visibleItemCount - 1, 0)) * itemSpacing
            return partialHeight
                + sectionTopPadding
                + sectionHeaderHeight
                + rowBlockHeight
                + intraRowSpacing
        }
    }

    private var inboxListViewportHeight: CGFloat {
        let preferredHeight = inboxListContentHeight > 0
            ? inboxListContentHeight
            : estimatedInboxListHeight
        return min(preferredHeight, LayoutMetrics.maxListHeight)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
            header

            if let unavailableState = model.startupUnavailableState {
                unavailableStateView(for: unavailableState)
            } else if model.hasToken {
                inboxSectionList
            } else {
                tokenSetup
            }

            footer
        }
        .padding(LayoutMetrics.contentPadding)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MenuBarContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            let count = model.inboxSectionItems.count
            Text("Inbox")
                .font(.headline)
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: requestMainWindow) {
                Image(systemName: "macwindow")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .appInteractiveHover(backgroundOpacity: 0.08, cornerRadius: 8)
            .help("Open Octowatch")
        }
    }

    private var inboxSectionList: some View {
        Group {
            if model.inboxSections.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text("Nothing in the inbox")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.inboxSections, id: \.name) { section in
                            Text(section.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, section.name == model.inboxSections.first?.name ? 0 : 8)

                            ForEach(section.items.prefix(10)) { item in
                                HStack(spacing: 6) {
                                    Button {
                                        requestMainWindow(for: item)
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            eventBadge(for: item)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.title)
                                                    .font(.callout.weight(.medium))
                                                    .lineLimit(1)
                                                Text(itemContext(for: item))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)
                                    .appInteractiveHover(backgroundOpacity: 0.06, cornerRadius: 10)
                                    .help("Open in Octowatch")

                                    Button {
                                        openURL(item.url)
                                    } label: {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 12, weight: .semibold))
                                            .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.plain)
                                    .appInteractiveHover(backgroundOpacity: 0.06, cornerRadius: 8)
                                    .help("Open on GitHub")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MenuBarListContentHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                }
                .frame(height: inboxListViewportHeight)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.hasToken, let lastError = model.lastError {
            HStack {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)

                Spacer()
            }
        }
    }

    private var tokenSetup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GitHub isn't connected yet.")
                .font(.callout.weight(.semibold))
            Text("Open Settings to validate GitHub CLI or provide a personal access token.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: requestSettings) {
                Text("Open Settings")
            }
            .appInteractiveHover()
        }
    }

    private func unavailableStateView(
        for state: AppStartupUnavailableState
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.title)
                .font(.callout.weight(.semibold))
            Text(state.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch state {
            case .connectionRequired:
                Button(action: requestSettings) {
                    Text("Open Settings")
                }
                .appInteractiveHover()
            case .offline:
                Button {
                    model.retryConnection()
                } label: {
                    Text("Retry")
                }
                .appInteractiveHover()
                .accessibilityIdentifier("menu-bar-offline-retry-button")
            }
        }
    }

    private func itemContext(for item: AttentionItem) -> String {
        AttentionItemPresentationPolicy.sidebarContext(for: item)
    }

    private func requestSettings() {
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }

    private func requestMainWindow() {
        NotificationCenter.default.post(name: .openMainWindowRequested, object: nil)
    }

    private func requestMainWindow(for item: AttentionItem) {
        let request = AttentionSubjectNavigationRequest(subjectKey: item.subjectKey)
        NotificationCenter.default.post(
            name: .openMainWindowRequested,
            object: nil,
            userInfo: request.userInfo
        )
    }

    @ViewBuilder
    private func eventBadge(for item: AttentionItem) -> some View {
        let helpText = AttentionItemType.badgeHelpText(
            primary: item.type,
            secondary: item.secondaryIndicatorType
        )

        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(item.type.badgeBackground)
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: item.type.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.type.badgeForeground)
            }
            .help(helpText)
            .accessibilityLabel(helpText)
    }

}

private struct MenuBarContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MenuBarListContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BotAccountChip: View {
    let login: String
    var compact: Bool = false

    var body: some View {
        Image(systemName: "cpu")
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 3 : 5)
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

private struct ActorAvatarView: View {
    let actor: AttentionActor

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
        .frame(width: 20, height: 20)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .help(actor.login)
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
    }
}

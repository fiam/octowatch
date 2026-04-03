import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.hasToken {
                inboxSectionList
            } else {
                tokenSetup
            }

            footer
        }
        .padding(12)
        .frame(width: 360)
        .onReceive(NotificationCenter.default.publisher(for: .performMainWindowOpen)) { _ in
            openWindow(id: AppSceneID.mainWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSettingsOpen)) { _ in
            openSettings()
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
                }
                .frame(maxHeight: 320)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let lastError = model.lastError {
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

    private func itemContext(for item: AttentionItem) -> String {
        let typeSummary = item.type.nativeNotificationTitle
        if let repo = item.repository {
            return "\(repo) · \(typeSummary)"
        }
        return typeSummary
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

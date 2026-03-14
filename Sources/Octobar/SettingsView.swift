import SwiftUI

struct SettingsView: View {
    private enum TokenSource: Hashable {
        case githubCLI
        case personalAccessToken
    }

    @ObservedObject var model: AppModel
    @Environment(\.openURL) private var openURL
    @FocusState private var tokenFieldFocused: Bool
    @State private var selectedTokenSource: TokenSource = .personalAccessToken

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tokenCard
                    pollingCard
                    ignoredItemsCard
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 760, height: 460)
        .onAppear {
            syncSelectedTokenSource()
            focusTokenFieldIfNeeded()
        }
        .onChange(of: model.usingGitHubCLIToken) { _, usingCLI in
            if usingCLI {
                selectedTokenSource = .githubCLI
            }
        }
    }

    private var tokenCard: some View {
        settingsCard {
            cardIntro(
                title: "GitHub Auth",
                message: tokenSummary
            ) {
                GitHubMarkBadge()
            }

            Divider()
                .padding(.horizontal, 20)

            settingsRow(
                title: "Authentication",
                subtitle: authSubtitle
            ) {
                if model.gitHubCLIAvailable {
                    Picker("Authentication", selection: tokenSourceSelection) {
                        Text("GitHub CLI").tag(TokenSource.githubCLI)
                        Text("Personal Access Token").tag(TokenSource.personalAccessToken)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                    .labelsHidden()
                } else {
                    Text("Personal Access Token")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .padding(.leading, 20)

            if selectedTokenSource == .githubCLI {
                settingsRow(
                    title: "GitHub CLI",
                    subtitle: "Octowatch validates `gh auth token` before using it."
                ) {
                    Button(model.usingGitHubCLIToken ? "Check Again" : "Use GitHub CLI") {
                        Task {
                            let success = await model.reloadTokenFromGitHubCLI()
                            if !success {
                                selectedTokenSource = .personalAccessToken
                                focusTokenFieldIfNeeded(force: true)
                            }
                        }
                    }
                    .disabled(model.isValidatingToken)
                }
            } else {
                customTokenEditor
            }

            if let error = model.lastError {
                Divider()
                    .padding(.leading, 20)

                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
        }
    }

    private var pollingCard: some View {
        settingsCard {
            cardIntro(
                title: "Refresh Interval",
                message: "Choose how often Octowatch refreshes GitHub activity."
            ) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.orange.gradient)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }

            Divider()
                .padding(.horizontal, 20)

            settingsRow(
                title: "Refresh Interval",
                subtitle: "Shorter intervals check more often but increase API traffic."
            ) {
                Picker(
                    "Refresh Interval",
                    selection: Binding(
                        get: { model.pollIntervalSeconds },
                        set: { model.setPollIntervalSeconds($0) }
                    )
                ) {
                    ForEach(model.pollIntervalOptions, id: \.self) { seconds in
                        Text(label(for: seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .labelsHidden()
            }
        }
    }

    private var ignoredItemsCard: some View {
        settingsCard {
            cardIntro(
                title: "Ignored Items",
                message: ignoredItemsSummary
            ) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.secondary.opacity(0.16))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }

            Divider()
                .padding(.horizontal, 20)

            if model.ignoredItems.isEmpty {
                settingsRow(
                    title: "No ignored items",
                    subtitle: "Ignored pull requests and issues will appear here so you can restore them later."
                ) {
                    EmptyView()
                }
            } else {
                ForEach(Array(model.ignoredItems.enumerated()), id: \.element.id) { index, ignoredItem in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 20)
                    }

                    settingsRow(
                        title: ignoredItem.title,
                        subtitle: ignoredItemSubtitle(for: ignoredItem)
                    ) {
                        HStack(spacing: 10) {
                            Button("Open") {
                                openURL(ignoredItem.url)
                            }
                            .buttonStyle(.bordered)

                            Button("Unignore") {
                                model.unignore(ignoredItem)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }

    private var customTokenEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Access Token")
                .font(.headline)

            Text("Octowatch validates the token before it starts using it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Personal access token", text: $model.tokenInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($tokenFieldFocused)

            HStack {
                Button("Apply Token") {
                    Task {
                        _ = await model.saveToken()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isValidatingToken)

                Button("Clear") {
                    model.clearToken()
                }
                .disabled(model.isValidatingToken || (!model.hasToken && model.tokenInput.isEmpty))

                if model.isValidatingToken {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var tokenSummary: String {
        if model.usingGitHubCLIToken {
            return "GitHub CLI was detected and its token validated automatically."
        }

        if model.gitHubCLIAvailable {
            return "Octowatch tries GitHub CLI first and falls back to a personal access token when needed."
        }

        return "GitHub CLI was not found, so use a personal access token."
    }

    private var authSubtitle: String {
        if model.gitHubCLIAvailable {
            return "Select a validated GitHub CLI token or provide a personal access token."
        }

        return "GitHub CLI is not installed, so use a personal access token."
    }

    private var ignoredItemsSummary: String {
        if model.ignoredItems.isEmpty {
            return "Restore pull requests or issues you previously decided to hide."
        }

        let count = model.ignoredItems.count
        return count == 1
            ? "1 item is currently hidden from the inbox."
            : "\(count) items are currently hidden from the inbox."
    }

    private var tokenSourceSelection: Binding<TokenSource> {
        Binding(
            get: {
                if model.gitHubCLIAvailable {
                    return selectedTokenSource
                }

                return .personalAccessToken
            },
            set: { newValue in
                if newValue == .githubCLI {
                    selectedTokenSource = .githubCLI
                    Task {
                        let success = await model.reloadTokenFromGitHubCLI()
                        if !success {
                            selectedTokenSource = .personalAccessToken
                            focusTokenFieldIfNeeded(force: true)
                        }
                    }
                    return
                }

                selectedTokenSource = .personalAccessToken
                focusTokenFieldIfNeeded(force: true)
            }
        )
    }

    private func syncSelectedTokenSource() {
        selectedTokenSource = model.usingGitHubCLIToken ? .githubCLI : .personalAccessToken
    }

    private func focusTokenFieldIfNeeded(force: Bool = false) {
        guard selectedTokenSource == .personalAccessToken || force else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            tokenFieldFocused = true
        }
    }

    private func label(for seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) seconds"
        }

        let minutes = seconds / 60
        if minutes == 1 {
            return "1 minute"
        }

        return "\(minutes) minutes"
    }

    private func ignoredItemSubtitle(for ignoredItem: IgnoredAttentionSubject) -> String {
        let relative = relativeFormatter.localizedString(
            for: ignoredItem.ignoredAt,
            relativeTo: Date()
        )
        return "\(ignoredItem.subtitle) · Ignored \(relative)"
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    private func cardIntro<Leading: View>(
        title: String,
        message: String,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            leading()

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    private func settingsRow<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            accessory()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct GitHubMarkBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .frame(width: 46, height: 46)
            .overlay {
                Image("GitHubMark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

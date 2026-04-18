import AppKit
import SwiftUI

struct SettingsView: View {
    private enum TokenSource: Hashable, CaseIterable, Identifiable {
        case githubCLI
        case personalAccessToken

        var id: Self { self }

        var title: String {
            switch self {
            case .githubCLI:
                return "GitHub CLI"
            case .personalAccessToken:
                return "Personal Access Token"
            }
        }

        var systemImage: String {
            switch self {
            case .githubCLI:
                return "terminal"
            case .personalAccessToken:
                return "key.horizontal.fill"
            }
        }
    }

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case general
        case github
        case inbox
        case localState
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                return "General"
            case .github:
                return "Authentication"
            case .inbox:
                return "Inbox"
            case .localState:
                return "Local State"
            case .advanced:
                return "Advanced"
            }
        }

        var iconName: String {
            switch self {
            case .general:
                return "gearshape"
            case .github:
                return "lock.shield"
            case .inbox:
                return "tray"
            case .localState:
                return "archivebox"
            case .advanced:
                return "ladybug"
            }
        }
    }

    private enum LayoutMetrics {
        static let detailMaxWidth: CGFloat = 500
        static let detailHorizontalPadding: CGFloat = 16
        static let detailTopPadding: CGFloat = 16
        static let detailBottomPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 20
        static let sidebarTopInset: CGFloat = 10
        static let sectionHeaderSpacing: CGFloat = 8
        static let sectionCornerRadius: CGFloat = 10
        static let sectionStrokeOpacity: Double = 0.12
    }

    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @FocusState private var tokenFieldFocused: Bool
    @State private var selectedTokenSource: TokenSource = .personalAccessToken
    @State private var selectedPane: SettingsPane = .general
    @State private var showsResetInboxSectionsConfirmation = false
    @State private var renamingSection: InboxSection?
    @State private var renamingSectionName = ""
    @State private var editingSectionForRules: InboxSection?
    @State private var showsPersonalAccessTokenHelp = false
    @State private var gitHubCLIReloadTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            settingsSidebar
        } detail: {
            settingsPaneContent {
                paneContent(for: selectedPane)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 460)
        .background(SettingsWindowConfigurator(windowTitle: selectedPane.title))
        .onAppear {
            syncSelectedTokenSource()
            syncSelectedPaneIfNeeded()
            applyPendingSettingsNavigationIfNeeded()
            focusTokenFieldIfNeeded()
        }
        .onChange(of: model.usingGitHubCLIToken) { _, usingCLI in
            if usingCLI {
                selectedTokenSource = .githubCLI
            }
        }
        .onChange(of: model.settingsNavigationTarget) { _, _ in
            applyPendingSettingsNavigationIfNeeded()
        }
        .onChange(of: selectedPane) { _, _ in
            focusTokenFieldIfNeeded()
        }
        .onDisappear {
            gitHubCLIReloadTask?.cancel()
            gitHubCLIReloadTask = nil
        }
        .confirmationDialog(
            "Reset Inbox Sections?",
            isPresented: $showsResetInboxSectionsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Defaults", role: .destructive) {
                model.resetInboxSections()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the default rule list and removes your custom edits.")
        }
        .sheet(item: $renamingSection) { section in
            VStack(spacing: 16) {
                Text("Rename Section")
                    .font(.headline)
                TextField("Section Name", text: $renamingSectionName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { renamingSection = nil }
                    Button("Rename") {
                        model.renameInboxSection(id: section.id, name: renamingSectionName)
                        renamingSection = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        .sheet(item: $editingSectionForRules) { section in
            SectionRulesSheet(
                sectionID: section.id,
                model: model,
                onDismiss: { editingSectionForRules = nil }
            )
        }
        .sheet(isPresented: $showsPersonalAccessTokenHelp) {
            PersonalAccessTokenHelpSheet(
                onOpenSettings: {
                    openURL(GitHubPersonalAccessTokenSetup.settingsURL)
                }
            )
        }
    }

    private var settingsSidebar: some View {
        List(SettingsPane.allCases, selection: $selectedPane) { pane in
            Label(pane.title, systemImage: pane.iconName)
                .tag(pane)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: LayoutMetrics.sidebarTopInset)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
    }

    private func settingsPaneContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                content()
            }
            .padding(.horizontal, LayoutMetrics.detailHorizontalPadding)
            .padding(.top, LayoutMetrics.detailTopPadding)
            .padding(.bottom, LayoutMetrics.detailBottomPadding)
            .frame(maxWidth: LayoutMetrics.detailMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func paneContent(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            generalPaneContent
        case .github:
            githubPaneContent
        case .inbox:
            inboxPaneContent
        case .localState:
            localStatePaneContent
        case .advanced:
            advancedPaneContent
        }
    }

    private var generalPaneContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(
                title: "Refreshing",
                summary: "Control how often Octowatch polls GitHub for new activity."
            ) {
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

            settingsSection(
                title: "Menu Bar",
                summary: "Choose whether Octowatch keeps a persistent status item in the menu bar."
            ) {
                settingsRow(
                    title: "Show Menu Bar Icon",
                    subtitle: "When on, clicking a menu bar item opens Octowatch by default and keeps GitHub as a secondary action."
                ) {
                    Toggle(
                        "Show Menu Bar Icon",
                        isOn: Binding(
                            get: { model.showsMenuBarIcon },
                            set: { model.setShowsMenuBarIcon($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
    }

    private var githubPaneContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(
                title: "GitHub",
                summary: tokenSummary
            ) {
                settingsStackedRow(
                    title: "Token Source",
                    subtitle: authSubtitle
                ) {
                    if model.gitHubCLIAvailable {
                        tokenSourceControl
                    } else {
                        Text("Personal Access Token")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = model.lastError {
                    settingsSectionDivider

                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }

            if selectedTokenSource == .githubCLI {
                settingsSection(
                    title: "GitHub CLI",
                    summary: "Reuse the GitHub CLI session that is already authenticated on this Mac."
                ) {
                    settingsStackedRow(
                        title: "Connection Status",
                        subtitle: model.gitHubCLIAuthStatus.detail
                    ) {
                        HStack(spacing: 12) {
                            authenticationStatusBadge(
                                model.gitHubCLIAuthStatus.stateLabel,
                                tone: statusTone(for: model.gitHubCLIAuthStatus)
                            )

                            Spacer()

                            Button(model.usingGitHubCLIToken ? "Check Again" : "Use GitHub CLI") {
                                reloadGitHubCLIToken(fallbackToPersonalAccessTokenOnFailure: false)
                            }
                            .disabled(model.isValidatingToken)
                            .appInteractiveHover()
                        }
                    }
                }
            } else {
                settingsSection(
                    title: "Personal Access Token",
                    summary: "Use this when you want Octowatch to manage authentication directly instead of reusing GitHub CLI."
                ) {
                    customTokenEditor
                }
            }
        }
    }

    private var inboxPaneContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(
                title: "Read State",
                summary: "Choose how items move from unread to read while you browse the inbox."
            ) {
                settingsRow(
                    title: "Auto-Mark as Read",
                    subtitle: "Marks an item read after it stays selected for the chosen delay."
                ) {
                    Picker(
                        "Auto-Mark as Read",
                        selection: Binding(
                            get: { model.autoMarkReadSetting },
                            set: { model.setAutoMarkReadSetting($0) }
                        )
                    ) {
                        ForEach(model.autoMarkReadOptions, id: \.self) { setting in
                            Text(setting.label).tag(setting)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .labelsHidden()
                }
            }

            settingsSection(
                title: "Notifications",
                summary: "Control whether Octowatch raises notifications for your own follow-up activity."
            ) {
                settingsRow(
                    title: "Notify on Your Updates",
                    subtitle: "When off, Octowatch keeps your own commits, comments, reviews, and workflows in the update history but does not raise macOS notifications for them."
                ) {
                    Toggle(
                        "Notify on Your Updates",
                        isOn: Binding(
                            get: { model.notifyOnSelfTriggeredUpdates },
                            set: { model.setNotifyOnSelfTriggeredUpdates($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            settingsSection(
                title: "Pinned Sections",
                summary: "Define the pinned sections at the top of your inbox. Items match the first section whose rules apply."
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(model.inboxSectionConfig.sections.enumerated()), id: \.element.id) { index, section in
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.name)
                                    .font(.body.weight(.medium))

                                Text(inboxSectionSummary(for: section))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 16)

                            Button("Edit Rules") {
                                editingSectionForRules = section
                            }
                            .appInteractiveHover()

                            Menu {
                                Button("Rename...") {
                                    renamingSectionName = section.name
                                    renamingSection = section
                                }
                                Toggle("Enabled", isOn: sectionToggleBinding(section))
                                Divider()
                                Button("Move Up") {
                                    moveSection(section, by: -1)
                                }
                                .disabled(index == 0)
                                Button("Move Down") {
                                    moveSection(section, by: 1)
                                }
                                .disabled(index == model.inboxSectionConfig.sections.count - 1)
                                Divider()
                                Button("Delete Section", role: .destructive) {
                                    model.deleteInboxSection(id: section.id)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if index < model.inboxSectionConfig.sections.count - 1 {
                            settingsSectionDivider
                        }
                    }

                    settingsSectionDivider

                    HStack {
                        Button("Add Section") {
                            model.addInboxSection(name: "New Section")
                        }
                        .appInteractiveHover()

                        Spacer()

                        Button("Reset Defaults") {
                            showsResetInboxSectionsConfirmation = true
                        }
                        .appInteractiveHover()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var localStatePaneContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(
                title: "Snoozed Items",
                summary: snoozedItemsSummary
            ) {
                settingsRow(
                    title: "Manage Snoozed Items",
                    subtitle: snoozedItemsManagementSubtitle
                ) {
                    Button("Open Snoozed Items") {
                        openWindow(id: AppSceneID.snoozedItemsWindow)
                    }
                    .buttonStyle(.bordered)
                    .appInteractiveHover()
                }
            }

            settingsSection(
                title: "Ignored Items",
                summary: ignoredItemsSummary
            ) {
                settingsRow(
                    title: "Manage Ignored Items",
                    subtitle: ignoredItemsManagementSubtitle
                ) {
                    Button("Open Ignored Items") {
                        openWindow(id: AppSceneID.ignoredItemsWindow)
                    }
                    .buttonStyle(.bordered)
                    .appInteractiveHover()
                }
            }
        }
    }

    private var advancedPaneContent: some View {
        settingsSection(
            title: "Diagnostics",
            summary: "Optional low-level API diagnostics for debugging refresh behavior."
        ) {
            settingsRow(
                title: "Show Rate-Limit Buckets",
                subtitle: "Displays per-bucket GitHub API budgets in the inbox sidebar."
            ) {
                Toggle(
                    "Show Rate-Limit Buckets",
                    isOn: Binding(
                        get: { model.showsDebugRateLimitDetails },
                        set: { model.setShowsDebugRateLimitDetails($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    private var customTokenEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("Personal access token", text: $model.tokenInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($tokenFieldFocused)
                .disabled(model.isValidatingToken)

            HStack {
                Button {
                    Task {
                        _ = await model.saveToken()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if model.isValidatingToken {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(model.isValidatingToken ? "Saving Token…" : "Save Token")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isValidatingToken || !canSavePersonalAccessToken)
                .appInteractiveHover()

                Button("How do I create a token?") {
                    showsPersonalAccessTokenHelp = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .underline()
                .disabled(model.isValidatingToken)
                .appLinkHover()

                Spacer()
            }

            Text(customTokenPersistenceSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var tokenSummary: String {
        if model.usingGitHubCLIToken {
            return "GitHub CLI was detected and its token validated automatically."
        }

        if model.usingKeychainStoredPersonalAccessToken {
            return "A personal access token was loaded from Keychain."
        }

        if model.usingPersonalAccessToken {
            if model.hasStoredPersonalAccessToken {
                return "A personal access token is active and saved in Keychain."
            }

            return "A personal access token is active for this session."
        }

        if model.gitHubCLIAvailable {
            return "Octowatch tries GitHub CLI first and falls back to a personal access token when needed."
        }

        return "GitHub CLI was not found, so use a personal access token."
    }

    private var tokenSourceControl: some View {
        HStack(spacing: 8) {
            ForEach(TokenSource.allCases) { source in
                authSourceButton(source)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeInOut(duration: 0.16), value: selectedTokenSource)
    }

    private var authSubtitle: String {
        if model.gitHubCLIAvailable {
            return "Select a validated GitHub CLI token or provide a personal access token that Octowatch saves in Keychain."
        }

        return "GitHub CLI is not installed, so use a personal access token. Octowatch saves it in Keychain for future launches."
    }

    private var canSavePersonalAccessToken: Bool {
        !model.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var customTokenPersistenceSummary: String {
        if model.hasStoredPersonalAccessToken {
            return "A personal access token is currently saved in Keychain. Saving a new token replaces it."
        }

        return "Octowatch validates the token before using it, then saves it in Keychain for future launches."
    }

    private func authSourceButton(_ source: TokenSource) -> some View {
        let isSelected = selectedTokenSource == source

        return Button {
            tokenSourceSelection.wrappedValue = source
        } label: {
            HStack(spacing: 8) {
                Image(systemName: source.systemImage)
                    .imageScale(.small)

                Text(source.title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
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
        .appInteractiveHover(backgroundOpacity: isSelected ? 0 : 0.06, cornerRadius: 999)
        .accessibilityLabel(source.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    private var ignoredItemsManagementSubtitle: String {
        if model.ignoredItems.isEmpty {
            return "Open a separate window to review ignored pull requests and issues as they accumulate."
        }

        return "Open a separate window to restore hidden pull requests and issues without crowding settings."
    }

    private var snoozedItemsSummary: String {
        if model.snoozedItems.isEmpty {
            return "Review items you temporarily hid until a later time."
        }

        let count = model.snoozedItems.count
        return count == 1
            ? "1 item is currently snoozed."
            : "\(count) items are currently snoozed."
    }

    private var snoozedItemsManagementSubtitle: String {
        if model.snoozedItems.isEmpty {
            return "Open a separate window to review snoozed pull requests and issues as they accumulate."
        }

        return "Open a separate window to restore snoozed items before their timer expires."
    }

    private func sectionToggleBinding(_ section: InboxSection) -> Binding<Bool> {
        Binding(
            get: {
                model.inboxSectionConfig.sections
                    .first(where: { $0.id == section.id })?
                    .isEnabled ?? section.isEnabled
            },
            set: { _ in
                model.toggleInboxSection(id: section.id)
            }
        )
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
                    reloadGitHubCLIToken(fallbackToPersonalAccessTokenOnFailure: true)
                    return
                }

                gitHubCLIReloadTask?.cancel()
                gitHubCLIReloadTask = nil
                selectedTokenSource = .personalAccessToken
                focusTokenFieldIfNeeded(force: true)
            }
        )
    }

    private func syncSelectedTokenSource() {
        selectedTokenSource = model.usingGitHubCLIToken ? .githubCLI : .personalAccessToken
    }

    private func syncSelectedPaneIfNeeded() {
        if !model.usingGitHubCLIToken && !model.hasToken {
            selectedPane = .github
        }
    }

    private func applyPendingSettingsNavigationIfNeeded() {
        guard let target = model.settingsNavigationTarget else {
            return
        }

        switch target {
        case let .authentication(preferredSource):
            selectedPane = .github
            switch preferredSource {
            case .githubCLI:
                selectedTokenSource = .githubCLI
            case .personalAccessToken:
                selectedTokenSource = .personalAccessToken
            }
            focusTokenFieldIfNeeded(force: preferredSource == .personalAccessToken)
        }

        model.consumeSettingsNavigationTarget()
    }

    private func focusTokenFieldIfNeeded(force: Bool = false) {
        guard selectedPane == .github else {
            return
        }

        guard selectedTokenSource == .personalAccessToken || force else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            tokenFieldFocused = true
        }
    }

    private func reloadGitHubCLIToken(
        fallbackToPersonalAccessTokenOnFailure: Bool
    ) {
        gitHubCLIReloadTask?.cancel()
        gitHubCLIReloadTask = Task {
            let success = await model.reloadTokenFromGitHubCLI()
            guard !Task.isCancelled else {
                return
            }

            if !success && fallbackToPersonalAccessTokenOnFailure {
                selectedTokenSource = .personalAccessToken
                focusTokenFieldIfNeeded(force: true)
            }
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

    private func inboxSectionSummary(for section: InboxSection) -> String {
        let enabledRules = section.enabledRuleCount
        let totalRules = section.ruleCount
        let ruleLabel = totalRules == 1 ? "rule" : "rules"
        return "\(enabledRules) of \(totalRules) \(ruleLabel) enabled"
    }

    private func moveSection(_ section: InboxSection, by offset: Int) {
        guard
            let currentIndex = model.inboxSectionConfig.sections.firstIndex(where: { $0.id == section.id })
        else {
            return
        }

        let targetIndex = currentIndex + offset
        guard model.inboxSectionConfig.sections.indices.contains(targetIndex) else {
            return
        }

        let destination = offset < 0 ? targetIndex : targetIndex + 1
        model.reorderInboxSections(
            fromOffsets: IndexSet(integer: currentIndex),
            toOffset: destination
        )
    }

    private func settingsSection<Content: View>(
        title: String,
        summary: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.sectionHeaderSpacing) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingsPanel {
                content()
            }
        }
    }

    private func settingsPanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: LayoutMetrics.sectionCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LayoutMetrics.sectionCornerRadius, style: .continuous)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(LayoutMetrics.sectionStrokeOpacity),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.sectionCornerRadius, style: .continuous))
    }

    private func settingsRow<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func settingsStackedRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func authenticationStatusBadge(
        _ title: String,
        tone: AuthenticationSettingsStatusTone
    ) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.background)
            )
    }

    private func statusTone(for status: GitHubCLIAuthStatus) -> AuthenticationSettingsStatusTone {
        switch status {
        case .ready:
            return .success
        case .tokenUnavailable:
            return .warning
        case .tokenRejected:
            return .critical
        case .checking:
            return .accent
        case .notInstalled:
            return .neutral
        }
    }

    private enum AuthenticationSettingsStatusTone {
        case accent
        case success
        case warning
        case critical
        case neutral

        var foreground: Color {
            switch self {
            case .accent:
                return .accentColor
            case .success:
                return .green
            case .warning:
                return .orange
            case .critical:
                return .red
            case .neutral:
                return .secondary
            }
        }

        var background: Color {
            switch self {
            case .accent:
                return Color.accentColor.opacity(0.14)
            case .success:
                return Color.green.opacity(0.14)
            case .warning:
                return Color.orange.opacity(0.14)
            case .critical:
                return Color.red.opacity(0.14)
            case .neutral:
                return Color.secondary.opacity(0.14)
            }
        }
    }

    private var settingsSectionDivider: some View {
        Divider()
            .padding(.leading, 14)
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    let windowTitle: String

    private static let initialContentSize = CGSize(width: 760, height: 500)
    private static let minimumContentSize = CGSize(width: 720, height: 460)

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else {
                return
            }

            window.identifier = AppWindowIdentifier.settings
            window.title = windowTitle
            window.titleVisibility = .visible
            window.toolbarStyle = .unifiedCompact
            window.titlebarSeparatorStyle = .line
            window.backgroundColor = .textBackgroundColor
            window.contentMinSize = Self.minimumContentSize

            if context.coordinator.configuredWindowNumber != window.windowNumber {
                context.coordinator.configuredWindowNumber = window.windowNumber
                window.setContentSize(Self.initialContentSize)
            }
        }
    }

    final class Coordinator {
        var configuredWindowNumber: Int?
    }
}

private struct PersonalAccessTokenHelpSheet: View {
    let onOpenSettings: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How to Create a Token")
                .font(.title3.weight(.semibold))

            Text(
                "If GitHub CLI is unavailable or not authenticated, create a classic personal access token with read access to the GitHub data Octowatch monitors."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                tokenHelpStep(
                    "Open GitHub token settings and create a classic personal access token."
                )
                tokenHelpStep(
                    "Grant read access to \(GitHubPersonalAccessTokenSetup.recommendedScopes.joined(separator: ", "))."
                )
                tokenHelpStep(
                    "Copy the token, paste it into Octowatch, and save it."
                )
            }

            Text(GitHubPersonalAccessTokenSetup.recommendedScopes.joined(separator: " · "))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Open GitHub Token Settings") {
                    onOpenSettings()
                }
                .keyboardShortcut(.defaultAction)

                Button("Done") {
                    dismiss()
                }

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func tokenHelpStep(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InboxRuleRow: View {
    let rule: InboxSectionRule
    @Binding var isEnabled: Bool

    private var typeIcon: (String, Color) {
        switch rule.itemKind {
        case .pullRequest: ("arrow.triangle.pull", .blue)
        case .issue: ("exclamationmark.circle", .orange)
        case .workflow: ("bolt.horizontal.circle", .purple)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Image(systemName: typeIcon.0)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(typeIcon.1)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(conditionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var conditionSummary: String {
        let normalized = rule.normalized
        let parts = normalized.conditions.map {
            $0.summaryPhrase(for: normalized.itemKind)
        }.filter { !$0.isEmpty }

        if parts.isEmpty {
            return "Matches all \(rule.itemKind.pluralTitle.lowercased())"
        }
        return parts.joined(separator: " · ")
    }
}

private struct InboxRuleClauseRow: View {
    @Binding var condition: InboxRuleCondition
    let itemKind: InboxRuleItemKind
    let onRemove: () -> Void

    private var dotColor: Color {
        switch condition.kind {
        case .relationship: return .blue
        case .signal: return .orange
        case .viewerReview: return .green
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            conditionContent

            Spacer()

            if condition.isNegated {
                Text("NOT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red.opacity(0.1)))
            }

            Button { onRemove() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(dotColor.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(dotColor.opacity(0.12), lineWidth: 1)
        )
        .contextMenu {
            Button(condition.isNegated ? "Remove negation" : "Negate (is not)") {
                condition.isNegated.toggle()
            }
        }
    }

    @ViewBuilder
    private var conditionContent: some View {
        switch condition.kind {
        case .relationship:
            relationshipPicker
        case .signal:
            signalPicker
        case .viewerReview:
            reviewPicker
        }
    }

    private var relationshipPicker: some View {
        let currentValue = condition.relationshipValues.first ?? .authored
        return Picker("", selection: Binding(
            get: { currentValue },
            set: { condition.relationshipValues = [$0] }
        )) {
            ForEach(itemKind.availableRelationships, id: \.self) { rel in
                Text(rel.title(for: itemKind)).tag(rel)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var signalPicker: some View {
        let currentValue = condition.signalValues.first ?? itemKind.availableSignals.first ?? .failedChecks
        return Picker("", selection: Binding(
            get: { currentValue },
            set: { condition.signalValues = [$0] }
        )) {
            ForEach(itemKind.availableSignals, id: \.self) { signal in
                Text(signal.title).tag(signal)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var reviewPicker: some View {
        Picker("", selection: $condition.viewerReviewValue) {
            Text("with your review").tag(InboxRuleReviewCondition.present)
            Text("without your review").tag(InboxRuleReviewCondition.missing)
        }
        .labelsHidden()
        .fixedSize()
    }
}

private struct SectionRulesSheet: View {
    let sectionID: UUID
    @ObservedObject var model: AppModel
    let onDismiss: () -> Void

    @State private var editingRuleID: InboxSectionRule.ID?

    private var section: InboxSection? {
        model.inboxSectionConfig.sections.first(where: { $0.id == sectionID })
    }

    var body: some View {
        Group {
            if let editingRuleID,
               let rule = section?.rules.first(where: { $0.id == editingRuleID }) {
                InboxRuleEditorView(
                    initialRule: rule,
                    onSave: { updatedRule in
                        model.saveInboxRule(updatedRule)
                        withAnimation { self.editingRuleID = nil }
                    },
                    onBack: {
                        withAnimation { self.editingRuleID = nil }
                    }
                )
            } else {
                rulesList
            }
        }
        .frame(width: 620, height: 520)
    }

    private var rulesList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(section?.name ?? "Section")
                    .font(.title2.weight(.semibold))
                Spacer()
                addRuleMenu
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            List {
                if let section {
                    ForEach(section.rules) { rule in
                        InboxRuleRow(
                            rule: rule,
                            isEnabled: Binding(
                                get: {
                                    model.inboxSectionConfig.sections
                                        .flatMap(\.rules)
                                        .first(where: { $0.id == rule.id })?
                                        .isEnabled ?? rule.isEnabled
                                },
                                set: { model.setInboxRuleEnabled(rule.id, isEnabled: $0) }
                            )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation { editingRuleID = rule.id }
                        }
                        .contextMenu {
                            Button("Duplicate") {
                                model.duplicateInboxRule(rule.id)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                model.deleteInboxRule(rule.id)
                            }
                        }
                    }
                    .onMove { from, to in
                        model.reorderInboxRules(
                            inSectionID: sectionID,
                            fromOffsets: from,
                            toOffset: to
                        )
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if section?.rules.isEmpty == true {
                    Text("No rules yet. Click + to get started.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }

    private var addRuleMenu: some View {
        Menu {
            ForEach(InboxRuleItemKind.allCases, id: \.self) { kind in
                Button {
                    let rule = model.addRuleToSection(sectionID: sectionID, itemKind: kind)
                    withAnimation { editingRuleID = rule.id }
                } label: {
                    Label(kind.pluralTitle, systemImage: kind.iconName)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Add rule")
    }
}

private struct InboxRuleEditorView: View {
    let initialRule: InboxSectionRule
    let onSave: (InboxSectionRule) -> Void
    let onBack: () -> Void

    @State private var draft: InboxSectionRule

    init(
        initialRule: InboxSectionRule,
        onSave: @escaping (InboxSectionRule) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.initialRule = initialRule
        self.onSave = onSave
        self.onBack = onBack
        _draft = State(initialValue: initialRule)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Edit Rule")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    onSave(draft.normalized)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            editorContent
        }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                itemKindRow
                conditionClauses
                Divider()
                previewSection
            }
            .padding(24)
        }
    }

    private var itemKindRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Show")
                .font(.title3)
                .foregroundStyle(.secondary)
            Label(draft.itemKind.pluralTitle, systemImage: draft.itemKind.iconName)
                .font(.title3.weight(.medium))
            Text("where:")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var conditionClauses: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(draft.conditions.enumerated()), id: \.element.id) { index, _ in
                InboxRuleClauseRow(
                    condition: $draft.conditions[index],
                    itemKind: draft.itemKind,
                    onRemove: {
                        withAnimation {
                            _ = draft.conditions.remove(at: index)
                        }
                    }
                )
            }

            addConditionMenu
        }
    }

    private var addConditionMenu: some View {
        Menu {
            ForEach(draft.itemKind.availableRelationships, id: \.self) { rel in
                Button(rel.title(for: draft.itemKind)) {
                    withAnimation {
                        draft.conditions.append(.relationship([rel]))
                    }
                }
            }

            if !draft.itemKind.availableSignals.isEmpty {
                Divider()
                ForEach(draft.itemKind.availableSignals, id: \.self) { signal in
                    Button(signal.title) {
                        withAnimation {
                            draft.conditions.append(.signal([signal]))
                        }
                    }
                }
            }

            if draft.itemKind.availableConditionKinds.contains(.viewerReview) {
                Divider()
                Button("With your review") {
                    withAnimation {
                        draft.conditions.append(.viewerReview(.present))
                    }
                }
                Button("Without your review") {
                    withAnimation {
                        draft.conditions.append(.viewerReview(.missing))
                    }
                }
            }
        } label: {
            Label("Add condition", systemImage: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.top, 4)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)

            InboxRuleRow(
                rule: draft.normalized,
                isEnabled: .constant(true)
            )
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func clauseIcon(for kind: InboxRuleConditionKind) -> String {
        switch kind {
        case .relationship: return "person"
        case .signal: return "exclamationmark.triangle"
        case .viewerReview: return "eye"
        }
    }
}

private struct LegacyInboxRuleEditorSheet_Unused: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: InboxSectionRule

    let onSave: (InboxSectionRule) -> Void
    let onCancel: () -> Void

    init(
        initialRule: InboxSectionRule,
        onSave: @escaping (InboxSectionRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: initialRule.normalized)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private func addCondition(
        _ kind: InboxRuleConditionKind,
        after index: Int? = nil
    ) {
        let newCondition = InboxRuleCondition.default(
            for: kind,
            itemKind: draft.itemKind
        )

        if let index {
            draft.conditions.insert(newCondition, at: index + 1)
        } else {
            draft.conditions.append(newCondition)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Section Rule")
                            .font(.title2.weight(.semibold))

                        Text("Define when items should appear in this section.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Show")

                            Picker("Item Type", selection: $draft.itemKind) {
                                ForEach(InboxRuleItemKind.allCases, id: \.self) { itemKind in
                                    Text(itemKind.pluralTitle).tag(itemKind)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()

                            Text("if all of the following conditions are met:")
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            if draft.conditions.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("No conditions yet.")
                                        .font(.body.weight(.medium))

                                    Text("This rule will match every \(draft.itemKind.pluralTitle.lowercased()) item until you add a condition.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Menu {
                                        ForEach(draft.itemKind.availableConditionKinds, id: \.self) { kind in
                                            Button(kind.title) {
                                                addCondition(kind)
                                            }
                                        }
                                    } label: {
                                        Label("Add Condition", systemImage: "plus")
                                    }
                                    .fixedSize()
                                }
                                .padding(16)
                            } else {
                                ForEach(Array(draft.conditions.enumerated()), id: \.element.id) { index, _ in
                                    InboxRuleConditionEditor(
                                        condition: $draft.conditions[index],
                                        itemKind: draft.itemKind,
                                        onAddCondition: { kind in
                                            addCondition(kind, after: index)
                                        },
                                        onRemove: {
                                            draft.conditions.remove(at: index)
                                        }
                                    )

                                    if index < draft.conditions.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Summary:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(draft.summary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Use multiple rules when you want separate scenarios to appear independently.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                    dismiss()
                }

                Button("Save Rule") {
                    onSave(draft.normalized)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 620, height: 480)
        .onChange(of: draft.itemKind) { _, newItemKind in
            var updatedDraft = draft.normalized
            updatedDraft.itemKind = newItemKind
            updatedDraft.conditions = updatedDraft.conditions.compactMap {
                $0.normalized(for: newItemKind)
            }

            if updatedDraft.conditions.isEmpty,
                let defaultKind = newItemKind.availableConditionKinds.first {
                updatedDraft.conditions = [
                    .default(for: defaultKind, itemKind: newItemKind)
                ]
            }

            draft = updatedDraft.normalized
        }
    }
}

private struct InboxRuleConditionEditor: View {
    @Binding var condition: InboxRuleCondition

    let itemKind: InboxRuleItemKind
    let onAddCondition: (InboxRuleConditionKind) -> Void
    let onRemove: () -> Void

    private var title: String {
        switch condition.kind {
        case .relationship:
            return "Relationship"
        case .signal:
            return "Signal"
        case .viewerReview:
            return "Your Review"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                invertButton

                Menu {
                    ForEach(itemKind.availableConditionKinds, id: \.self) { kind in
                        Button(kind.title) {
                            onAddCondition(kind)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add condition")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .help("Remove condition")
            }

            switch condition.kind {
            case .relationship:
                conditionCheckboxGrid {
                    ForEach(itemKind.availableRelationships, id: \.self) { relationship in
                        Toggle(
                            relationship.title(for: itemKind),
                            isOn: relationshipBinding(for: relationship)
                        )
                        .toggleStyle(.checkbox)
                    }
                }
            case .signal:
                conditionCheckboxGrid {
                    ForEach(itemKind.availableSignals, id: \.self) { signal in
                        Toggle(
                            signal.title,
                            isOn: signalBinding(for: signal)
                        )
                        .toggleStyle(.checkbox)
                    }
                }
            case .viewerReview:
                Picker("Your Review", selection: $condition.viewerReviewValue) {
                    ForEach(InboxRuleReviewCondition.allCases, id: \.self) { reviewCondition in
                        Text(reviewCondition.title).tag(reviewCondition)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .padding(16)
    }

    private var invertButton: some View {
        Button {
            condition.isNegated.toggle()
        } label: {
            Text("Invert")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(condition.isNegated ? .white : .primary)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            condition.isNegated
                                ? Color.accentColor
                                : Color(nsColor: .controlBackgroundColor)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            condition.isNegated
                                ? Color.accentColor.opacity(0.85)
                                : Color(nsColor: .separatorColor).opacity(0.45),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .appInteractiveHover(
            backgroundOpacity: condition.isNegated ? 0 : 0.08,
            cornerRadius: 999
        )
        .help(condition.isNegated ? "This condition is inverted" : "Invert this condition")
    }

    @ViewBuilder
    private func conditionCheckboxGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
    }

    private func relationshipBinding(
        for relationship: InboxRuleRelationship
    ) -> Binding<Bool> {
        Binding(
            get: { condition.relationshipValues.contains(relationship) },
            set: { isEnabled in
                if isEnabled {
                    condition.relationshipValues.insert(relationship)
                } else {
                    condition.relationshipValues.remove(relationship)
                }
            }
        )
    }

    private func signalBinding(for signal: InboxRuleSignal) -> Binding<Bool> {
        Binding(
            get: { condition.signalValues.contains(signal) },
            set: { isEnabled in
                if isEnabled {
                    condition.signalValues.insert(signal)
                } else {
                    condition.signalValues.remove(signal)
                }
            }
        )
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

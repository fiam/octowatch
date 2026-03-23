import SwiftUI

struct SettingsView: View {
    private enum TokenSource: Hashable {
        case githubCLI
        case personalAccessToken
    }

    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @FocusState private var tokenFieldFocused: Bool
    @State private var selectedTokenSource: TokenSource = .personalAccessToken
    @State private var editingNeedsActionRule: NeedsActionRuleDefinition?
    @State private var showsResetNeedsActionRulesConfirmation = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tokenCard
                    pollingCard
                    inboxCard
                    diagnosticsCard
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
        .sheet(item: $editingNeedsActionRule) { rule in
            NeedsActionRuleEditorSheet(
                initialRule: rule,
                onSave: { updatedRule in
                    editingNeedsActionRule = nil
                    model.saveNeedsActionRule(updatedRule)
                },
                onCancel: {
                    editingNeedsActionRule = nil
                }
            )
        }
        .confirmationDialog(
            "Reset Needs Action Rules?",
            isPresented: $showsResetNeedsActionRulesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Defaults", role: .destructive) {
                model.resetNeedsActionRules()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the default rule list and removes your custom edits.")
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
                    .appInteractiveHover()
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

            settingsRow(
                title: "Manage Ignored Items",
                subtitle: ignoredItemsManagementSubtitle
            ) {
                Button("Open Ignored Items") {
                    openWindow(id: AppSceneID.ignoredItemsWindow)
                }
                .buttonStyle(.borderedProminent)
                .appInteractiveHover()
            }
        }
    }

    private var diagnosticsCard: some View {
        settingsCard {
            cardIntro(
                title: "Diagnostics",
                message: "Optional low-level API diagnostics for debugging refresh behavior."
            ) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.purple.opacity(0.15))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "ladybug")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
            }

            Divider()
                .padding(.horizontal, 20)

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

    private var inboxCard: some View {
        settingsCard {
            cardIntro(
                title: "Inbox",
                message: "Choose how the inbox handles read state, self-triggered notifications, and the Needs Action section."
            ) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.blue.gradient)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }

            Divider()
                .padding(.horizontal, 20)

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

            Divider()
                .padding(.leading, 20)

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

            Divider()
                .padding(.leading, 20)

            settingsRow(
                title: "Needs Action Rules",
                subtitle: "Build the rules that decide what appears in the Needs Action section."
            ) {
                HStack(spacing: 10) {
                    Button("Reset Defaults") {
                        showsResetNeedsActionRulesConfirmation = true
                    }
                    .appInteractiveHover()

                    Button("Add Rule") {
                        editingNeedsActionRule = NeedsActionRuleDefinition.newCustom()
                    }
                    .buttonStyle(.borderedProminent)
                    .appInteractiveHover()
                }
            }

            ForEach(Array(model.needsActionConfiguration.rules.enumerated()), id: \.element.id) { index, rule in
                if index > 0 {
                    Divider()
                        .padding(.leading, 20)
                }

                needsActionRuleRow(rule)
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
                .appInteractiveHover()

                Button("Clear") {
                    model.clearToken()
                }
                .disabled(model.isValidatingToken || (!model.hasToken && model.tokenInput.isEmpty))
                .appInteractiveHover()

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

    private var ignoredItemsManagementSubtitle: String {
        if model.ignoredItems.isEmpty {
            return "Open a separate window to review ignored pull requests and issues as they accumulate."
        }

        return "Open a separate window to restore hidden pull requests and issues without crowding settings."
    }

    private func needsActionRuleRow(_ rule: NeedsActionRuleDefinition) -> some View {
        settingsRow(
            title: rule.summary,
            subtitle: ""
        ) {
            HStack(spacing: 10) {
                Toggle(
                    rule.summary,
                    isOn: Binding(
                        get: {
                            model.needsActionConfiguration.rules
                                .first(where: { $0.id == rule.id })?
                                .isEnabled ?? rule.isEnabled
                        },
                        set: { model.setNeedsActionRuleEnabled(rule.id, isEnabled: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)

                Button("Edit") {
                    editingNeedsActionRule = rule
                }
                .appInteractiveHover()

                Menu {
                    Button("Duplicate") {
                        model.duplicateNeedsActionRule(rule.id)
                    }

                    Button("Delete", role: .destructive) {
                        model.deleteNeedsActionRule(rule.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
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

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 24)

            accessory()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct NeedsActionRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: NeedsActionRuleDefinition

    let onSave: (NeedsActionRuleDefinition) -> Void
    let onCancel: () -> Void

    init(
        initialRule: NeedsActionRuleDefinition,
        onSave: @escaping (NeedsActionRuleDefinition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: initialRule.normalized)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private func addCondition(
        _ kind: NeedsActionConditionKind,
        after index: Int? = nil
    ) {
        let newCondition = NeedsActionCondition.default(
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
                        Text("Needs Action Rule")
                            .font(.title2.weight(.semibold))

                        Text("Build a rule for the work that should rise to the top when it needs something from you.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Show")

                            Picker("Item Type", selection: $draft.itemKind) {
                                ForEach(NeedsActionItemKind.allCases, id: \.self) { itemKind in
                                    Text(itemKind.pluralTitle).tag(itemKind)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()

                            Text("in Needs Action if all of the following conditions are met:")
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
                                    NeedsActionConditionEditor(
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
                            Text("Shows in Needs Action:")
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

private struct NeedsActionConditionEditor: View {
    @Binding var condition: NeedsActionCondition

    let itemKind: NeedsActionItemKind
    let onAddCondition: (NeedsActionConditionKind) -> Void
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
                            relationship.title,
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
                    ForEach(NeedsActionViewerReviewCondition.allCases, id: \.self) { reviewCondition in
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
        for relationship: NeedsActionViewerRelationship
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

    private func signalBinding(for signal: NeedsActionSignal) -> Binding<Bool> {
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

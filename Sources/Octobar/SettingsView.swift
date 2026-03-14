import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @FocusState private var tokenFieldFocused: Bool
    @State private var showCustomTokenEditor = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.96, green: 0.96, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                tokenCard
                pollingCard
                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .frame(width: 560, height: 360)
        .onAppear {
            if model.gitHubCLIAvailable, !model.usingGitHubCLIToken {
                showCustomTokenEditor = true
            }

            if (!model.gitHubCLIAvailable || showCustomTokenEditor), !model.hasToken {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    tokenFieldFocused = true
                }
            }
        }
        .onChange(of: model.usingGitHubCLIToken) { _, usingCLI in
            if usingCLI {
                showCustomTokenEditor = false
            }
        }
    }

    private var tokenCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("GitHub Token", systemImage: "key.horizontal")

                if model.gitHubCLIAvailable {
                    Text("GitHub CLI detected. Octobar reads your token from `gh auth token` at runtime and never writes to Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Reload from gh") {
                            model.reloadTokenFromGitHubCLI()
                        }
                        .buttonStyle(.borderedProminent)

                        Text(model.usingGitHubCLIToken ? "Using gh token (default)" : "Using custom session token")
                            .font(.caption)
                            .foregroundStyle(model.hasToken ? .green : .secondary)
                    }

                    if model.usingGitHubCLIToken, !showCustomTokenEditor {
                        Button("Use Custom Token…") {
                            showCustomTokenEditor = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                tokenFieldFocused = true
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if showCustomTokenEditor || !model.usingGitHubCLIToken {
                        SecureField("ghp_...", text: $model.tokenInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .focused($tokenFieldFocused)

                        HStack(spacing: 10) {
                            Button("Use Custom Token") {
                                model.saveToken()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Use gh Default") {
                                model.reloadTokenFromGitHubCLI()
                            }
                            .buttonStyle(.bordered)

                            Button("Clear Token") {
                                model.clearToken()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!model.hasToken)
                        }
                    }
                } else {
                    Text("GitHub CLI not found. Provide a token for this session only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("ghp_...", text: $model.tokenInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($tokenFieldFocused)

                    HStack(spacing: 10) {
                        Button("Use Session Token") {
                            model.saveToken()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Clear Token") {
                            model.clearToken()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.hasToken)
                    }
                }

                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var pollingCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Polling", systemImage: "clock.arrow.circlepath")

                Picker(
                    "Poll Interval",
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
                .frame(maxWidth: 220, alignment: .leading)
            }
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .labelStyle(.titleAndIcon)
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

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            )
    }
}

import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("GitHub Personal Access Token") {
                SecureField("ghp_...", text: $model.tokenInput)

                HStack {
                    Button("Save Token") {
                        model.saveToken()
                    }

                    if model.hasToken {
                        Button("Clear Token") {
                            model.clearToken()
                        }
                    }
                }

                Text("Octobar stores the token in Keychain and uses it to poll your assigned pull requests, actionable notifications, action_required workflow runs, and post-merge workflow outcomes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Polling") {
                Toggle(
                    "Poll every 60 seconds",
                    isOn: Binding(
                        get: { model.pollingEnabled },
                        set: { model.setPollingEnabled($0) }
                    )
                )
                .disabled(!model.hasToken)

                Button("Refresh Now") {
                    model.refreshNow()
                }
                .disabled(!model.hasToken)
            }

            if model.hasToken {
                Section("Current Watch") {
                    Text("Post-merge failures: \(model.postMergeFailureItems.count)")
                    Text("Merged PRs being watched: \(model.postMergeWatchItems.count)")
                }
            }

            if let error = model.lastError {
                Section("Last Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

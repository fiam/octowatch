import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var attentionItems: [AttentionItem] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    @Published var tokenInput = ""
    @Published var pollingEnabled = true

    private let tokenAccount = "github-personal-access-token"
    private let readStateStoreKey = "attention-item-read-state-v1"
    private let keychain = KeychainStore(service: "dev.octobar.app")
    private let client = GitHubClient()
    private let notifier = UserNotifier()

    private var token: String?
    private var userLogin: String?
    private var pollingTask: Task<Void, Never>?
    private var knownItemIDs = Set<String>()
    private var readStateByItemID: [String: Date] = [:]
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    init() {
        token = keychain.read(account: tokenAccount)
        tokenInput = token ?? ""
        readStateByItemID = Self.loadReadState(from: UserDefaults.standard, key: readStateStoreKey)

        Task {
            await notifier.requestAuthorization()
        }

        if hasToken {
            startPollingIfNeeded()
        } else {
            Task { [weak self] in
                await self?.importTokenFromGitHubCLIIfAvailable()
            }
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    var hasToken: Bool {
        !(token ?? "").isEmpty
    }

    var actionableCount: Int {
        attentionItems.count
    }

    var unreadCount: Int {
        attentionItems.filter { $0.isUnread }.count
    }

    var relativeLastUpdated: String {
        guard let lastUpdated else {
            return "Not refreshed yet"
        }

        let relative = relativeDateFormatter.localizedString(for: lastUpdated, relativeTo: Date())
        return "Updated \(relative)"
    }

    func saveToken() {
        let cleaned = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            clearToken()
            return
        }

        guard keychain.save(value: cleaned, account: tokenAccount) else {
            lastError = "Failed to save token in Keychain."
            return
        }

        token = cleaned
        knownItemIDs.removeAll()
        lastError = nil

        startPollingIfNeeded()
        refreshNow()
    }

    func clearToken() {
        _ = keychain.delete(account: tokenAccount)

        token = nil
        tokenInput = ""
        attentionItems = []
        userLogin = nil
        lastUpdated = nil
        lastError = nil
        knownItemIDs.removeAll()

        pollingTask?.cancel()
        pollingTask = nil
    }

    func setPollingEnabled(_ enabled: Bool) {
        pollingEnabled = enabled

        if enabled {
            startPollingIfNeeded()
            refreshNow()
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    func refreshNow() {
        Task {
            await refresh(force: true)
        }
    }

    func markItemAsRead(_ item: AttentionItem) {
        updateReadState(for: item, isUnread: false)
    }

    func toggleReadState(for item: AttentionItem) {
        updateReadState(for: item, isUnread: !item.isUnread)
    }

    private func startPollingIfNeeded() {
        guard hasToken, pollingEnabled else {
            return
        }

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refresh(force: true)

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled {
                    return
                }
                await self.refresh(force: false)
            }
        }
    }

    private func refresh(force: Bool) async {
        guard hasToken else {
            return
        }

        guard pollingEnabled || force else {
            return
        }

        guard let token else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = try await client.fetchSnapshot(token: token, preferredLogin: userLogin)
            userLogin = snapshot.login
            attentionItems = snapshot.attentionItems.map(applyingLocalReadState)
            lastUpdated = Date()
            lastError = nil

            notifyIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func importTokenFromGitHubCLIIfAvailable() async {
        guard !hasToken else {
            return
        }

        guard let cliToken = await GitHubCLITokenProvider.fetchToken() else {
            return
        }

        tokenInput = cliToken
        saveToken()
    }

    private func notifyIfNeeded() {
        let currentIDs = Set(attentionItems.map(\.id))

        let newItems = currentIDs.subtracting(knownItemIDs)
        if !knownItemIDs.isEmpty, !newItems.isEmpty {
            let count = newItems.count
            let suffix = count == 1 ? "" : "s"
            notifier.notify(
                title: "Octobar",
                body: "\(count) new GitHub item\(suffix) need attention."
            )
        }

        knownItemIDs = currentIDs
    }

    private func applyingLocalReadState(to item: AttentionItem) -> AttentionItem {
        var updated = item
        let locallyUnread = isLocallyUnread(item)
        updated.isUnread = item.isUnread && locallyUnread
        return updated
    }

    private func isLocallyUnread(_ item: AttentionItem) -> Bool {
        guard let readAt = readStateByItemID[item.id] else {
            return true
        }
        return readAt < item.timestamp
    }

    private func updateReadState(for item: AttentionItem, isUnread: Bool) {
        if isUnread {
            readStateByItemID[item.id] = nil
        } else {
            readStateByItemID[item.id] = Date()
        }

        persistReadState()

        if let index = attentionItems.firstIndex(where: { $0.id == item.id }) {
            attentionItems[index].isUnread = isUnread
        }
    }

    private func persistReadState() {
        let raw = readStateByItemID.mapValues(\.timeIntervalSince1970)
        UserDefaults.standard.set(raw, forKey: readStateStoreKey)
    }

    private static func loadReadState(from defaults: UserDefaults, key: String) -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: Double] else {
            return [:]
        }

        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }
}

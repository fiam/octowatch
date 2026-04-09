import XCTest
@testable import Octowatch

final class NotificationPresentationTests: XCTestCase {
    func testSecurityAlertReasonMapsToDedicatedAttentionType() {
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "security_alert",
                timelineEvent: nil,
                reviewState: nil
            ),
            .securityAlert
        )
    }

    func testSecurityAlertReasonIsNotOverriddenByCommentTimeline() {
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "security_alert",
                timelineEvent: "commented",
                reviewState: nil
            ),
            .securityAlert
        )
    }

    func testDependabotAlertAPIURLResolvesToSecurityAlertWebURL() {
        let client = GitHubClient()

        XCTAssertEqual(
            client.subjectWebURL(
                subjectURL: URL(string: "https://api.github.com/repos/fiam/dc2/dependabot/alerts/42"),
                repositoryWebURL: URL(string: "https://github.com/fiam/dc2")!,
                subjectType: "RepositoryVulnerabilityAlert"
            ),
            URL(string: "https://github.com/fiam/dc2/security/dependabot/42")!
        )
    }

    func testRepositoryVulnerabilityFallbackUsesDependabotPage() {
        let client = GitHubClient()

        XCTAssertEqual(
            client.subjectWebURL(
                subjectURL: nil,
                repositoryWebURL: URL(string: "https://github.com/fiam/dc2")!,
                subjectType: "RepositoryVulnerabilityAlert"
            ),
            URL(string: "https://github.com/fiam/dc2/security/dependabot")!
        )
    }

    func testDependabotThreadFallbackUsesDependabotPage() {
        let client = GitHubClient()

        XCTAssertEqual(
            client.subjectWebURL(
                subjectURL: nil,
                repositoryWebURL: URL(string: "https://github.com/acme/compose-private")!,
                subjectType: "RepositoryDependabotAlertsThread"
            ),
            URL(string: "https://github.com/acme/compose-private/security/dependabot")!
        )
    }

    func testSecurityAlertWebURLUsesSpecificOpenActionTitle() {
        let client = GitHubClient()

        XCTAssertEqual(
            client.openActionTitle(
                for: URL(string: "https://github.com/fiam/dc2/security/dependabot/42")!
            ),
            "Open Security Alert"
        )
    }

    func testDependabotIndexUsesSpecificOpenActionTitle() {
        let client = GitHubClient()

        XCTAssertEqual(
            client.openActionTitle(
                for: URL(string: "https://github.com/acme/compose-private/security/dependabot")!
            ),
            "Open Security Alert"
        )
    }

    func testNotificationThreadQueryIncludesReadAndUnreadThreads() {
        let client = GitHubClient()
        let queryItems = client.notificationThreadQueryItems(page: 3)
        let query = Dictionary(
            uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") }
        )

        XCTAssertEqual(query["all"], "true")
        XCTAssertEqual(query["per_page"], "50")
        XCTAssertEqual(query["page"], "3")
    }
}

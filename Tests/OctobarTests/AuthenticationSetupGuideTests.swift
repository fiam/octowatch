import XCTest
@testable import Octowatch

final class AuthenticationSetupGuideTests: XCTestCase {
    func testGuideExplainsManualSetupWhenGitHubCLIMissing() {
        let guide = AuthenticationStartupGuide(
            context: .recovery,
            gitHubCLIStatus: .notInstalled,
            personalAccessTokenStatus: .unavailable
        )

        XCTAssertTrue(guide.requiresManualIntervention)
        XCTAssertEqual(
            guide.summary,
            "GitHub CLI was not found. Manual setup is required."
        )
        XCTAssertTrue(
            guide.nextSteps.contains("Create a personal access token on GitHub.")
        )
    }

    func testGuideExplainsManualSetupWhenGitHubCLITokenNeedsAttention() {
        let guide = AuthenticationStartupGuide(
            context: .recovery,
            gitHubCLIStatus: .tokenRejected,
            personalAccessTokenStatus: .unavailable
        )

        XCTAssertTrue(guide.requiresManualIntervention)
        XCTAssertEqual(
            guide.summary,
            "GitHub CLI was found, but its token needs attention."
        )
        XCTAssertTrue(
            guide.nextSteps.contains("Run `gh auth login` to refresh GitHub CLI credentials.")
        )
    }

    func testStoredPersonalAccessTokenCancelsManualIntervention() {
        let guide = AuthenticationStartupGuide(
            context: .recovery,
            gitHubCLIStatus: .tokenUnavailable,
            personalAccessTokenStatus: .storedInKeychain
        )

        XCTAssertFalse(guide.requiresManualIntervention)
    }

    func testOnboardingGuideExplainsGitHubCLIWillBeUsedWhenReady() {
        let guide = AuthenticationStartupGuide(
            context: .onboarding,
            gitHubCLIStatus: .ready,
            personalAccessTokenStatus: .unavailable
        )

        XCTAssertFalse(guide.requiresManualIntervention)
        XCTAssertEqual(guide.title, "Welcome to Octowatch")
        XCTAssertEqual(
            guide.summary,
            "GitHub CLI was found and Octowatch will use it to authenticate."
        )
        XCTAssertTrue(
            guide.nextSteps.contains("Continue with the detected authentication to finish setup.")
        )
    }
}

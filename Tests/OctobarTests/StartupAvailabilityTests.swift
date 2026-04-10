import XCTest
@testable import Octowatch

final class StartupAvailabilityTests: XCTestCase {
    func testOfflineUnavailableStateUsesConnectivitySpecificCopy() {
        XCTAssertEqual(AppStartupUnavailableState.offline.title, "You're Offline")
        XCTAssertEqual(AppStartupUnavailableState.offline.systemImage, "wifi.slash")
        XCTAssertTrue(
            AppStartupUnavailableState.offline.description.contains(
                "retry automatically when the connection comes back"
            )
        )
    }

    func testConnectionRequiredStatePointsToSettings() {
        XCTAssertEqual(
            AppStartupUnavailableState.connectionRequired.title,
            "GitHub Connection Required"
        )
        XCTAssertEqual(
            AppStartupUnavailableState.connectionRequired.systemImage,
            "person.crop.circle.badge.exclamationmark"
        )
        XCTAssertTrue(
            AppStartupUnavailableState.connectionRequired.description.contains(
                "Open Settings"
            )
        )
    }

    func testOfflineClientErrorUsesOfflineDescription() {
        XCTAssertEqual(
            GitHubClientError.offline.localizedDescription,
            "You're offline. Octowatch will retry when the connection returns."
        )
    }

    func testTransportClientErrorPreservesTransportMessage() {
        XCTAssertEqual(
            GitHubClientError.transport(message: "Network request failed.")
                .localizedDescription,
            "Network request failed."
        )
    }
}

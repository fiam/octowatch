import Foundation
import Sparkle

@MainActor
final class AppUpdateController: NSObject {
    static let shared = AppUpdateController()

    let isAvailable: Bool
    private let updaterController: SPUStandardUpdaterController?

    override init() {
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""

        if feedURL.isEmpty || publicKey.isEmpty {
            isAvailable = false
            updaterController = nil
        } else {
            isAvailable = true
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }

        super.init()
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

import AppKit
import Darwin
import XCTest

func terminateRunningOctowatchIfNeeded(timeout: TimeInterval = 5) {
    let bundleIdentifier = "dev.octowatch.app"
    let deadline = Date().addingTimeInterval(timeout)

    while true {
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )

        guard !runningApps.isEmpty else {
            return
        }

        for app in runningApps {
            if !app.terminate() {
                kill(app.processIdentifier, SIGKILL)
            }
        }

        if Date() >= deadline {
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ) {
                kill(app.processIdentifier, SIGKILL)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            XCTFail("Failed to terminate \(bundleIdentifier) before launching UI test.")
            return
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}

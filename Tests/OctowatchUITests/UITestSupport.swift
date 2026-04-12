import AppKit
import Darwin
import Foundation
import ImageIO
import XCTest

private let octowatchBundleIdentifier = "dev.octowatch.app"

func terminateRunningOctowatchIfNeeded(timeout: TimeInterval = 5) {
    let deadline = Date().addingTimeInterval(timeout)

    while true {
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: octowatchBundleIdentifier
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
                withBundleIdentifier: octowatchBundleIdentifier
            ) {
                kill(app.processIdentifier, SIGKILL)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            XCTFail("Failed to terminate \(octowatchBundleIdentifier) before launching UI test.")
            return
        }

        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}

@MainActor
func launchFixture(named fixtureName: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["OCTOWATCH_UI_TEST_FIXTURE"] = fixtureName
    app.launch()
    return app
}

@MainActor
func makeWindowScreenshotAttachment(named name: String, for app: XCUIApplication) -> XCTAttachment {
    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 5))
    let screenshot = window.screenshot()
    let attachment: XCTAttachment

    if let croppedImage = cropWindowScreenshot(screenshot, to: window.frame) {
        attachment = XCTAttachment(image: croppedImage)
    } else {
        attachment = XCTAttachment(screenshot: screenshot)
    }

    attachment.name = name
    attachment.lifetime = .keepAlways
    return attachment
}

@MainActor
private func cropWindowScreenshot(
    _ screenshot: XCUIScreenshot,
    to windowFrame: CGRect
) -> NSImage? {
    guard
        let source = CGImageSourceCreateWithData(screenshot.pngRepresentation as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        return nil
    }

    let screenshotSize = screenshot.image.size
    guard screenshotSize.width > 0, screenshotSize.height > 0 else {
        return nil
    }

    let scaleX = CGFloat(image.width) / screenshotSize.width
    let scaleY = CGFloat(image.height) / screenshotSize.height
    let paddingX = 24.0 * scaleX
    let paddingY = 24.0 * scaleY
    let cropRect = CGRect(
        x: windowFrame.minX * scaleX - paddingX,
        y: (screenshotSize.height - windowFrame.maxY) * scaleY - paddingY,
        width: windowFrame.width * scaleX + (paddingX * 2),
        height: windowFrame.height * scaleY + (paddingY * 2)
    ).integral

    let imageBounds = CGRect(
        x: 0,
        y: 0,
        width: CGFloat(image.width),
        height: CGFloat(image.height)
    )
    let clampedRect = cropRect.intersection(imageBounds)

    guard !clampedRect.isNull, !clampedRect.isEmpty else {
        return nil
    }

    guard let croppedImage = image.cropping(to: clampedRect) else {
        return nil
    }

    return NSImage(
        cgImage: croppedImage,
        size: NSSize(
            width: clampedRect.width / scaleX,
            height: clampedRect.height / scaleY
        )
    )
}

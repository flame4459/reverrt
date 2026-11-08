import XCTest

/// End-to-end exercise of the live ride: start, pause, resume, calibrate,
/// stop, save, and the summary hand-off.
final class RiderFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-debugSeedRide", "-skipOnboarding"]
        app.launch()

        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        sleep(4)
        app.tap()
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            app.terminate()
        }
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func dump(_ label: String) {
        print("=== HIERARCHY \(label) START ===")
        print(app.debugDescription)
        print("=== HIERARCHY \(label) END ===")
    }

    @discardableResult
    private func tapButton(_ label: String, timeout: TimeInterval = 8) -> Bool {
        let element = app.buttons[label].firstMatch
        guard element.waitForExistence(timeout: timeout) else {
            print("MISSING BUTTON: \(label)")
            return false
        }
        element.tap()
        sleep(1)
        return true
    }

    private func waitForText(_ label: String, timeout: TimeInterval) -> Bool {
        app.staticTexts[label].firstMatch.waitForExistence(timeout: timeout)
    }

    @discardableResult
    private func scroll(to label: String, maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes {
            let element = app.staticTexts[label].firstMatch
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return app.staticTexts[label].firstMatch.exists
    }

    func testRecordRideAndSummary() {
        XCTAssertTrue(tapButton("Ride"), "Ride screen should open")
        sleep(2)
        attach("40-ride-ready")
        dump("RIDE_READY")

        XCTAssertTrue(tapButton("Start ride"), "Ride should start")
        sleep(8)
        attach("41-ride-recording")

        XCTAssertTrue(tapButton("Pause"), "Pause should be available")
        sleep(2)
        attach("42-ride-paused")

        XCTAssertTrue(tapButton("Resume"), "Resume should be available")
        sleep(4)

        _ = tapButton("Calibrate lean angle", timeout: 2)

        XCTAssertTrue(tapButton("Stop"), "Stop should be available")
        sleep(1)
        attach("43-ride-stop-confirm")
        dump("RIDE_STOP_CONFIRM")

        XCTAssertTrue(tapButton("Save Ride"), "Save Ride in confirmation")
        let summary = waitForText("RIDE SAVED", timeout: 15)
        XCTAssertTrue(summary, "Summary should appear after saving")
        attach("44-ride-summary")
        dump("RIDE_SUMMARY")

        if tapButton("Done", timeout: 5) {
            sleep(2)
            attach("45-back-home-after-ride")
        }
    }

    func testHistoryDetailPoster() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        sleep(1)
        let historyTile = app.staticTexts["Ride history"].firstMatch
        XCTAssertTrue(historyTile.waitForExistence(timeout: 5), "Ride history tile")
        historyTile.tap()
        sleep(3)
        attach("50-history")
        dump("HISTORY")

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Top'")).firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap()
            sleep(4)
            attach("51-ride-detail")
            dump("RIDE_DETAIL")

            // Replay, metric switch, then the poster studio.
            if app.buttons.matching(identifier: "play.fill").firstMatch.exists {
                app.buttons.matching(identifier: "play.fill").firstMatch.tap()
                sleep(3)
                attach("52-ride-replay")
            }
            let lean = app.buttons["Lean"].firstMatch.exists ? app.buttons["Lean"].firstMatch : app.staticTexts["Lean"].firstMatch
            if lean.exists {
                lean.tap()
                sleep(2)
                attach("53-ride-lean-heatmap")
            }
            let poster = app.buttons["Create a story poster"].firstMatch
            if poster.waitForExistence(timeout: 4) {
                poster.tap()
                sleep(3)
                attach("54-poster-studio")
                dump("POSTER")
            }
        } else {
            print("MISSING RIDE ROW")
        }
    }

    func testPosterRender() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        let historyTile = app.staticTexts["Ride history"].firstMatch
        XCTAssertTrue(historyTile.waitForExistence(timeout: 5))
        historyTile.tap()
        sleep(3)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Top'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Ride row")
        row.tap()
        sleep(4)
        let poster = app.buttons["Create a story poster"].firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 4))
        poster.tap()
        sleep(2)
        if app.buttons["Ride journal"].firstMatch.exists {
            app.buttons["Ride journal"].firstMatch.tap()
            sleep(1)
        }
        attach("55-poster-journal")
        XCTAssertTrue(tapButton("Render poster"), "Render poster")
        let rendered = app.buttons["Share poster"].firstMatch.waitForExistence(timeout: 20)
        attach("56-poster-rendered")
        dump("POSTER_RENDERED")
        XCTAssertTrue(rendered, "Poster file should be generated")
    }

    func testImportShareAndOfflineDownload() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        let historyTile = app.staticTexts["Ride history"].firstMatch
        XCTAssertTrue(historyTile.waitForExistence(timeout: 5))
        historyTile.tap()
        sleep(3)

        if app.buttons["Import GPX"].firstMatch.exists {
            app.buttons["Import GPX"].firstMatch.tap()
            sleep(3)
            attach("60-gpx-importer")
            if app.buttons["Cancel"].firstMatch.exists {
                app.buttons["Cancel"].firstMatch.tap()
                sleep(1)
            }
        } else {
            print("MISSING IMPORT BUTTON")
        }

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Top'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        sleep(4)
        attach("61-detail-toolbar")
        let share = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Share'")).firstMatch
        if share.exists {
            share.tap()
            sleep(3)
            attach("62-share-sheet")
            // Activity sheet close button is usually "Close" or the grabber.
            if app.buttons["Close"].firstMatch.exists {
                app.buttons["Close"].firstMatch.tap()
            } else {
                app.swipeDown()
            }
            sleep(1)
        } else {
            print("MISSING SHARE BUTTON")
            dump("DETAIL_TOOLBAR")
        }

        // Leave the detail stack and open Offline data.
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        if app.buttons["Close history"].firstMatch.exists {
            app.buttons["Close history"].firstMatch.tap()
            sleep(1)
        }
        if !app.buttons["Expand ride planner"].firstMatch.exists {
            _ = tapButton("Expand ride planner")
        }
        _ = scroll(to: "Offline data", maxSwipes: 4)
        if app.staticTexts["Offline data"].firstMatch.exists {
            app.staticTexts["Offline data"].firstMatch.tap()
            sleep(2)
            if app.buttons["Download around my location"].firstMatch.exists {
                app.buttons["Download around my location"].firstMatch.tap()
                sleep(6)
                attach("63-offline-download")
                dump("OFFLINE_DOWNLOAD")
            }
            if app.buttons["Done"].firstMatch.exists {
                app.buttons["Done"].firstMatch.tap()
            }
        }
    }

    func testOfflineDownload() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        _ = scroll(to: "Offline data", maxSwipes: 4)
        let tile = app.staticTexts["Offline data"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        sleep(2)
        XCTAssertTrue(tapButton("Download around my location"))
        sleep(8)
        attach("70-offline-progress")
        dump("OFFLINE_PROGRESS")
        if app.buttons["Done"].firstMatch.exists {
            app.buttons["Done"].firstMatch.tap()
        }
    }
}

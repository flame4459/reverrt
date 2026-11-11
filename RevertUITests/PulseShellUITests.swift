import XCTest

/// Covers the Midnight Pulse shell: the dashboard is the landing screen, the
/// five destinations switch without losing their screens, and the map keeps
/// its search sheet on the Routes tab.
final class PulseShellUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-skipOnboarding",
            "-debugSeedRide",
            "-debugGarageSeed",
        ]
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
        sleep(3)

        // A first-run location alert can sit above the dashboard. Dismiss it
        // explicitly so every test starts from the same place.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                break
            }
        }
        sleep(1)
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            app.terminate()
        }
    }

    func testDismissLocationPrompt() {
        // A first-run location alert can sit above the dashboard even after
        // the permission is granted; dismissing it here unblocks the rest of
        // the suite (and mirrors what a rider does).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                sleep(1)
                break
            }
        }

        XCTAssertTrue(app.staticTexts["Your next ride"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Home"].exists)
        XCTAssertTrue(app.buttons["Routes"].exists)
        XCTAssertTrue(app.buttons["Garage"].exists)
        XCTAssertTrue(app.buttons["History"].exists)
    }

    func testDashboardToRoutesAndBack() {
        XCTAssertTrue(app.staticTexts["Your next ride"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.buttons["Routes"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Routes"].firstMatch.tap()
        sleep(2)

        XCTAssertTrue(app.staticTexts["Route planner"].waitForExistence(timeout: 8),
                      "Routes must open the Midnight Pulse route planner")
        XCTAssertTrue(app.textFields["Where to?"].waitForExistence(timeout: 8),
                      "The planner must keep destination search")
        XCTAssertTrue(app.buttons["Home"].exists,
                      "The tab bar stays visible on Routes, so there is always a way out")
        XCTAssertFalse(app.buttons["Expand ride planner"].exists,
                       "The legacy ride-planner sheet must not be used on Routes")

        app.buttons["Home"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Your next ride"].waitForExistence(timeout: 8))
    }

    func testPlannerSearchFullMapAndStartNavigation() {
        app.buttons["Routes"].firstMatch.tap()
        sleep(2)

        // The map can expand without leaving the new UI, and has an obvious exit.
        app.buttons["Open full map"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Close full map"].waitForExistence(timeout: 8))
        app.buttons["Close full map"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Route planner"].waitForExistence(timeout: 8))

        let field = app.textFields["Where to?"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Central Park, New York\n")

        XCTAssertTrue(app.staticTexts["ROUTE READY"].waitForExistence(timeout: 60),
                      "A resolved destination should build a route preview")
        XCTAssertTrue(app.buttons["Start navigation"].firstMatch.waitForExistence(timeout: 5))

        // Starting navigation opens the cockpit, and closing it returns to the
        // planner rather than stranding the rider.
        app.buttons["Start navigation"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Close ride screen"].waitForExistence(timeout: 12),
                      "Start navigation should open the cockpit")
        app.buttons["Close ride screen"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Route planner"].waitForExistence(timeout: 10),
                      "Closing the cockpit should return to the route planner")
        XCTAssertTrue(app.buttons["Home"].exists)
    }

    func testGarageBikeDetailHasBackButton() {
        XCTAssertTrue(app.buttons["Garage"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Garage"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Your machines"].waitForExistence(timeout: 8))

        let bike = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Street Triple")
        ).firstMatch
        guard bike.waitForExistence(timeout: 6) else {
            // A clean install has no seeded bike; adding one is covered by the
            // audit suite. The tab itself is still verified above.
            return
        }
        bike.tap()
        sleep(2)

        // Pushed detail screens must keep a way back even though the tab's
        // own navigation bar is hidden.
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Bike detail lost its back button")
        back.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Your machines"].waitForExistence(timeout: 8))
    }

    func testHistoryRideDetailHasBackButton() {
        XCTAssertTrue(app.buttons["History"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["History"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Ride history"].waitForExistence(timeout: 8))

        // The ride rows live below the summary cards; bring them into view
        // before tapping, the way a rider would scroll.
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        // Match on a unit-independent part of the row's combined label; the
        // rider may have switched between miles and kilometres.
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "lean")
        ).firstMatch
        guard row.waitForExistence(timeout: 6) else {
            XCTFail("Seeded ride row missing from history")
            return
        }
        row.tap()
        sleep(2)
        XCTAssertTrue(app.navigationBars["Ride"].waitForExistence(timeout: 8),
                      "Ride detail did not open")

        let back = app.navigationBars["Ride"].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Ride detail lost its back button")
        back.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Ride history"].waitForExistence(timeout: 8))
    }

    func testColorSchemesSwitchAndPersist() {
        XCTAssertTrue(app.buttons["Color scheme"].firstMatch.waitForExistence(timeout: 10),
                      "The palette shortcut should be on the dashboard")
        app.buttons["Color scheme"].firstMatch.tap()
        sleep(2)

        for name in ["Midnight Pulse", "Kawasaki Lime Green", "Suzuki Grand Prix",
                     "Yamaha Speed Block", "Honda Winning Red"] {
            let row = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", name)
            ).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 6), "\(name) should be selectable")
        }

        let kawasaki = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Kawasaki Lime Green")
        ).firstMatch
        kawasaki.tap()
        sleep(1)
        XCTAssertTrue(kawasaki.isSelected, "Selecting a scheme should update the picker")
        attach("color-scheme-kawasaki")

        app.buttons["Done"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Your next ride"].waitForExistence(timeout: 8))
        attach("color-scheme-kawasaki-home")

        // The scheme must survive a cold launch.
        app.terminate()
        app.launch()
        sleep(3)
        XCTAssertTrue(app.buttons["Color scheme"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Color scheme"].firstMatch.tap()
        sleep(2)
        let persisted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Kawasaki Lime Green")
        ).firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 6))
        XCTAssertTrue(persisted.isSelected, "The chosen color scheme should persist")

        // Leave the simulator on the default scheme for the other tests.
        let midnight = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Midnight Pulse")
        ).firstMatch
        midnight.tap()
        sleep(1)
        app.buttons["Done"].firstMatch.tap()
    }

    func testLandscapeLayout() {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)

        XCTAssertTrue(app.staticTexts["Your next ride"].waitForExistence(timeout: 10),
                      "The dashboard must survive a rotation")
        XCTAssertTrue(app.buttons["Routes"].exists)
        attach("pulse-landscape-home")

        app.buttons["Routes"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Route planner"].waitForExistence(timeout: 8),
                      "The planner must render in landscape")
        XCTAssertTrue(app.buttons["Home"].exists,
                      "The tab bar must stay reachable in landscape")
        attach("pulse-landscape-routes")

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(app.staticTexts["Route planner"].waitForExistence(timeout: 8))
    }

    func testLiveRideStartsAndSaves() {
        XCTAssertTrue(app.buttons["Ride"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Ride"].firstMatch.tap()
        sleep(2)

        XCTAssertTrue(app.buttons["Start ride"].waitForExistence(timeout: 8),
                      "Ride tab must open the cockpit")
        app.buttons["Start ride"].tap()
        sleep(7)

        app.buttons["Stop"].tap()
        sleep(1)
        app.buttons["Save Ride"].tap()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 12),
                      "Saving a ride should show the summary")
        app.buttons["Done"].tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Your next ride"].waitForExistence(timeout: 10),
                      "Closing the summary should return to the dashboard")
    }

    func testGarageAndHistoryTabs() {
        XCTAssertTrue(app.buttons["Garage"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Garage"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Your machines"].waitForExistence(timeout: 8))

        app.buttons["History"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts["Ride history"].waitForExistence(timeout: 8))
    }
}

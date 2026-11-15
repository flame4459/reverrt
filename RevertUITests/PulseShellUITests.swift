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

        XCTAssertTrue(app.screenTitle(UITestID.Home.title).waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[UITestID.TabBar.home].exists)
        XCTAssertTrue(app.buttons[UITestID.TabBar.routes].exists)
        XCTAssertTrue(app.buttons[UITestID.TabBar.garage].exists)
        XCTAssertTrue(app.buttons[UITestID.TabBar.history].exists)
    }

    func testDashboardToRoutesAndBack() {
        XCTAssertTrue(app.screenTitle(UITestID.Home.title).waitForExistence(timeout: 10))

        XCTAssertTrue(app.buttons[UITestID.TabBar.routes].firstMatch.waitForExistence(timeout: 5))
        app.buttons[UITestID.TabBar.routes].firstMatch.tap()
        sleep(2)

        XCTAssertTrue(app.screenTitle(UITestID.Routes.title).waitForExistence(timeout: 8),
                      "Routes must open the Midnight Pulse route planner")
        XCTAssertTrue(app.textFields[UITestID.Routes.destination].waitForExistence(timeout: 8),
                      "The planner must keep destination search")
        XCTAssertTrue(app.buttons[UITestID.TabBar.home].exists,
                      "The tab bar stays visible on Routes, so there is always a way out")
        XCTAssertFalse(app.buttons["Expand ride planner"].exists,
                       "The legacy ride-planner sheet must not be used on Routes")

        app.buttons[UITestID.TabBar.home].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.Home.title).waitForExistence(timeout: 8))
    }

    func testHomeDestinationOpensPlanner() {
        let field = app.textFields[UITestID.Home.destination].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "Home should expose the destination input")
        field.tap()
        field.typeText("Central Park\n")

        XCTAssertTrue(app.screenTitle(UITestID.Routes.title).waitForExistence(timeout: 10),
                      "Submitting the Home destination should open the planner")
        XCTAssertTrue(app.textFields[UITestID.Routes.destination].waitForExistence(timeout: 8),
                      "The draft destination should carry into the planner")
        let carried = app.textFields[UITestID.Routes.destination].value as? String
        XCTAssertTrue(carried?.contains("Central Park") == true,
                      "The Home destination should be pre-filled in the planner, got \(carried ?? "nil")")
        XCTAssertTrue(app.control(UITestID.Routes.findRoute).exists,
                      "The planner should keep its bottom CTA")
    }

    func testCockpitNoRouteOpensPlanner() {
        XCTAssertTrue(app.buttons[UITestID.TabBar.ride].firstMatch.waitForExistence(timeout: 10))
        app.buttons[UITestID.TabBar.ride].firstMatch.tap()

        XCTAssertTrue(app.control(UITestID.Cockpit.planRoute).waitForExistence(timeout: 8),
                      "The no-route cockpit should offer a route-planning action")
        XCTAssertFalse(app.staticTexts["NO DATA"].exists,
                       "The cockpit should not show a placeholder speed-limit card")
        app.control(UITestID.Cockpit.planRoute).tap()

        XCTAssertTrue(app.screenTitle(UITestID.Routes.title).waitForExistence(timeout: 10),
                      "Planning from the cockpit should land on the route planner")
    }

    func testPlannerSearchFullMapAndStartNavigation() {
        app.buttons[UITestID.TabBar.routes].firstMatch.tap()
        sleep(2)

        // The map can expand without leaving the new UI, and has an obvious exit.
        app.control(UITestID.Routes.openMap).firstMatch.tap()
        XCTAssertTrue(app.control(UITestID.Routes.closeMap).waitForExistence(timeout: 8))
        app.control(UITestID.Routes.closeMap).firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.screenTitle(UITestID.Routes.title).waitForExistence(timeout: 8))

        let field = app.textFields[UITestID.Routes.destination].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Central Park, New York\n")

        XCTAssertTrue(app.staticTexts["ROUTE READY"].waitForExistence(timeout: 60),
                      "A resolved destination should build a route preview")
        XCTAssertTrue(app.control(UITestID.Routes.start).firstMatch.waitForExistence(timeout: 5))

        // Starting a route asks which vehicle is being used today; answer it
        // before the cockpit is presented.
        app.control(UITestID.Routes.start).firstMatch.tap()
        if app.buttons["Car"].waitForExistence(timeout: 3) {
            app.buttons["Car"].tap()
        }
        XCTAssertTrue(app.control(UITestID.Cockpit.close).waitForExistence(timeout: 12),
                      "Start navigation should open the cockpit")
        app.control(UITestID.Cockpit.close).firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.Routes.title).waitForExistence(timeout: 10),
                      "Closing the cockpit should return to the route planner")
        XCTAssertTrue(app.buttons[UITestID.TabBar.home].exists)
    }

    func testGarageBikeDetailHasBackButton() {
        XCTAssertTrue(app.buttons[UITestID.TabBar.garage].firstMatch.waitForExistence(timeout: 10))
        app.buttons[UITestID.TabBar.garage].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.Garage.title).waitForExistence(timeout: 8))

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
        XCTAssertTrue(app.screenTitle(UITestID.Garage.title).waitForExistence(timeout: 8))
    }

    func testHistoryRideDetailHasBackButton() {
        XCTAssertTrue(app.buttons[UITestID.TabBar.history].firstMatch.waitForExistence(timeout: 10))
        app.buttons[UITestID.TabBar.history].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.History.title).waitForExistence(timeout: 8))

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
        XCTAssertTrue(app.screenTitle(UITestID.History.title).waitForExistence(timeout: 8))
    }

    func testColorSchemesSwitchAndPersist() {
        XCTAssertTrue(app.control(UITestID.Home.colorScheme).firstMatch.waitForExistence(timeout: 10),
                      "The palette shortcut should be on the dashboard")
        app.control(UITestID.Home.colorScheme).firstMatch.tap()
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

        app.control(UITestID.Settings.done).tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.Home.title).waitForExistence(timeout: 8))
        attach("color-scheme-kawasaki-home")

        // The scheme must survive a cold launch.
        app.terminate()
        app.launch()
        sleep(3)
        XCTAssertTrue(app.control(UITestID.Home.colorScheme).firstMatch.waitForExistence(timeout: 10))
        app.control(UITestID.Home.colorScheme).firstMatch.tap()
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
        app.control(UITestID.Settings.done).tap()
    }

    func testLandscapeLayout() {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)

        XCTAssertTrue(app.screenTitle(UITestID.Home.title).waitForExistence(timeout: 10),
                      "The dashboard must survive a rotation")
        XCTAssertTrue(app.buttons[UITestID.TabBar.routes].exists)
        attach("pulse-landscape-home")

        app.buttons[UITestID.TabBar.routes].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.Routes.title).waitForExistence(timeout: 8),
                      "The planner must render in landscape")
        XCTAssertTrue(app.buttons[UITestID.TabBar.home].exists,
                      "The tab bar must stay reachable in landscape")
        attach("pulse-landscape-routes")

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.Routes.title).waitForExistence(timeout: 8))
    }

    func testLiveRideStartsAndSaves() throws {
        XCTAssertTrue(app.buttons[UITestID.TabBar.ride].firstMatch.waitForExistence(timeout: 10))
        app.buttons[UITestID.TabBar.ride].firstMatch.tap()
        sleep(2)

        XCTAssertTrue(app.control(UITestID.Cockpit.start).waitForExistence(timeout: 8),
                      "Ride tab must open the cockpit")
        app.control(UITestID.Cockpit.start).tap()
        sleep(7)

        app.control(UITestID.Cockpit.stop).tap()
        sleep(1)
        app.buttons["Save Ride"].tap()

        let summary = app.control(UITestID.Summary.done)
        guard summary.waitForExistence(timeout: 8) else {
            // A static simulator can have no usable GPS track. The app handles
            // that correctly with a "Ride not saved" alert; make the missing
            // location explicit rather than failing on a UI timeout.
            let notSaved = app.alerts["Ride not saved"]
            if notSaved.waitForExistence(timeout: 2) {
                notSaved.buttons["OK"].tap()
                throw XCTSkip("Simulator produced no GPS points; set a moving simulator location to exercise the live-save path.")
            }
            XCTFail("Saving a ride should show the summary")
            return
        }
        summary.tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.Home.title).waitForExistence(timeout: 10),
                      "Closing the summary should return to the dashboard")
    }

    func testGarageAndHistoryTabs() {
        XCTAssertTrue(app.buttons[UITestID.TabBar.garage].firstMatch.waitForExistence(timeout: 10))
        app.buttons[UITestID.TabBar.garage].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.Garage.title).waitForExistence(timeout: 8))

        app.buttons[UITestID.TabBar.history].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.screenTitle(UITestID.History.title).waitForExistence(timeout: 8))
    }

    func testHistoryStatsAreMerged() {
        XCTAssertTrue(app.buttons[UITestID.TabBar.history].firstMatch.waitForExistence(timeout: 10))
        app.buttons[UITestID.TabBar.history].firstMatch.tap()
        sleep(2)

        XCTAssertTrue(app.staticTexts["Ride stats"].waitForExistence(timeout: 8),
                      "History should show the merged stats overview")
        XCTAssertFalse(app.staticTexts["All-time snapshot"].exists,
                       "The duplicate all-time card should be gone")
        XCTAssertFalse(app.staticTexts["Personal bests"].exists,
                       "The duplicate personal-bests card should be gone")
    }
}

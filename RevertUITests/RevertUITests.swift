import XCTest

final class RevertUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-saved.home.lat", "37.7749",
            "-saved.home.lon", "-122.4194",
            "-debugSeedRide", "-skipOnboarding"
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

        sleep(4)
        // The map is the Routes destination in the Midnight Pulse shell.
        if app.buttons["Routes"].waitForExistence(timeout: 3) {
            app.buttons["Routes"].tap()
            sleep(2)
        }
        app.tap()
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            app.terminate()
        }
    }

    // MARK: - Helpers

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

    private func tapStaticText(_ label: String, timeout: TimeInterval = 8) -> Bool {
        let element = app.staticTexts[label].firstMatch
        guard element.waitForExistence(timeout: timeout) else {
            print("MISSING TEXT: \(label)")
            return false
        }
        element.tap()
        sleep(1)
        return true
    }

    private func scroll(to label: String, maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes {
            let element = app.staticTexts[label].firstMatch
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return app.staticTexts[label].firstMatch.exists
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) { return true }
            usleep(300_000)
        }
        return false
    }

    // MARK: - Tests

    func testHomeSearchAndRoute() {
        attach("00-home")

        XCTAssertTrue(tapButton("Home"), "Home chip should work on the compact planner")
        sleep(1)
        attach("01-home-pin")
        dump("HOME_PIN")

        XCTAssertTrue(tapButton("Expand ride planner"), "Planner should expand")
        sleep(1)
        attach("02-expanded-with-destination")

        XCTAssertTrue(tapButton("Preview route", timeout: 5), "Preview should be available")
        let resultsShown = waitForAny([
            app.staticTexts["ROUTE OPTIONS"].firstMatch,
            app.buttons["Start navigation"].firstMatch,
            app.staticTexts["Start navigation"].firstMatch
        ], timeout: 30)
        attach("03-route-results")
        dump("ROUTE_RESULTS")

        if resultsShown {
            if app.buttons["Save route"].firstMatch.exists {
                app.buttons["Save route"].firstMatch.tap()
                sleep(1)
                attach("04-route-saved")
            }
            if app.buttons["Start navigation"].firstMatch.exists {
                app.buttons["Start navigation"].firstMatch.tap()
                sleep(3)
                attach("05-ride-from-route")
                dump("RIDE")
                if app.buttons["Close ride screen"].firstMatch.exists {
                    app.buttons["Close ride screen"].firstMatch.tap()
                    sleep(1)
                }
            }
        } else {
            print("NO ROUTE RESULTS")
        }

        // Search UI: type a destination and verify suggestions appear.
        if app.buttons["Close route preview"].firstMatch.exists {
            app.buttons["Close route preview"].firstMatch.tap()
            sleep(1)
        }
        if !app.textFields["Where to?"].firstMatch.exists && !app.textFields["Search destination"].firstMatch.exists {
            _ = tapButton("Expand ride planner")
        }
        let clear = app.buttons["Clear destination"].firstMatch
        if clear.exists {
            clear.tap()
            sleep(1)
        }
        if !app.buttons["Expand ride planner"].firstMatch.exists && !app.textFields["Where to?"].firstMatch.exists {
            _ = tapButton("Expand ride planner")
        }
        let field = app.textFields["Where to?"].firstMatch.exists
            ? app.textFields["Where to?"].firstMatch
            : app.textFields["Search destination"].firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("Ferry Building")
            sleep(7)
            attach("06-search-suggestions")
            dump("SEARCH_SUGGESTIONS")
            field.typeText("\n")
            sleep(2)
            attach("07-search-submit")
        } else {
            print("MISSING SEARCH FIELD")
        }
    }

    func testRouteOnly() {
        XCTAssertTrue(tapButton("Home"), "Home chip")
        sleep(1)
        XCTAssertTrue(tapButton("Expand ride planner"))
        XCTAssertTrue(tapButton("Preview route", timeout: 5))
        let resultsShown = waitForAny([
            app.staticTexts["ROUTE OPTIONS"].firstMatch,
            app.buttons["Start navigation"].firstMatch
        ], timeout: 35)
        attach("route-only")
        dump("ROUTE_ONLY")
        XCTAssertTrue(resultsShown)
    }

    func testSettings() {
        XCTAssertTrue(tapButton("Ride menu"))
        sleep(1)
        XCTAssertTrue(tapButton("App settings"), "Settings menu item")
        sleep(2)
        attach("10-settings-top")
        dump("SETTINGS_TOP")

        let metric = app.switches["Metric (km, km/h, metres)"].firstMatch
        if metric.waitForExistence(timeout: 4) {
            metric.tap()
            sleep(1)
            attach("11-settings-metric")
        } else {
            print("MISSING METRIC TOGGLE")
        }

        if app.staticTexts["Bike model"].firstMatch.exists {
            app.staticTexts["Bike model"].firstMatch.tap()
            sleep(2)
            attach("12-bike-picker")
            dump("BIKE_PICKER")
            if app.buttons["Close bike picker"].firstMatch.exists {
                app.buttons["Close bike picker"].firstMatch.tap()
                sleep(1)
            }
        } else {
            print("MISSING BIKE MODEL ROW")
        }

        // Scroll through the safety cards and exercise a few toggles.
        app.swipeUp()
        app.swipeUp()
        attach("13-settings-scrolled")
        for label in ["Stop signs", "Traffic lights", "Railroad crossings", "School zones"] {
            let toggle = app.switches[label].firstMatch
            if toggle.waitForExistence(timeout: 2) {
                toggle.tap()
                sleep(1)
            } else {
                print("MISSING TOGGLE: \(label)")
            }
        }
        attach("14-settings-toggles")
        dump("SETTINGS_SCROLLED")
    }

    func testGarage() {
        XCTAssertTrue(tapButton("Ride menu"))
        sleep(1)
        XCTAssertTrue(tapButton("App settings"))
        sleep(1)

        let metric = app.switches["Metric (km, km/h, metres)"].firstMatch
        if metric.exists, (metric.value as? String) == "1" {
            metric.tap()
            sleep(1)
        }

        let garageLink = app.staticTexts["Garage, fuel range & maintenance"].firstMatch
        XCTAssertTrue(garageLink.waitForExistence(timeout: 5), "Garage link")
        garageLink.tap()
        sleep(2)
        attach("20-garage-empty")
        dump("GARAGE_EMPTY")

        if app.buttons["Add a bike"].firstMatch.exists {
            app.buttons["Add a bike"].firstMatch.tap()
        } else if app.buttons["Add another bike"].firstMatch.exists {
            app.buttons["Add another bike"].firstMatch.tap()
        }
        sleep(2)
        attach("21-bike-editor")

        let nickname = app.textFields["Nickname"].firstMatch
        if nickname.waitForExistence(timeout: 5) {
            nickname.tap()
            nickname.typeText("Test Bike")
            let make = app.textFields["Make"].firstMatch
            make.tap(); make.typeText("Yamaha")
            let model = app.textFields["Model"].firstMatch
            model.tap(); model.typeText("MT-07")
            app.buttons["Save"].firstMatch.tap()
            sleep(2)
            attach("22-garage-bike")
            dump("GARAGE_BIKE")
        } else {
            print("MISSING BIKE FORM")
        }

        let bikeCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test Bike'")).firstMatch
        if bikeCard.waitForExistence(timeout: 4) {
            bikeCard.tap()
            sleep(2)
            attach("23-bike-detail")
            if app.buttons["Log"].firstMatch.exists {
                app.buttons["Log"].firstMatch.tap()
                sleep(1)
                let title = app.textFields["What did you do? (oil, tyres, chain…)"].firstMatch
                if title.waitForExistence(timeout: 3) {
                    title.tap(); title.typeText("Oil change")
                }
                app.buttons["Save"].firstMatch.tap()
                sleep(2)
                attach("24-maintenance-log")
                dump("BIKE_DETAIL")
            }
        } else {
            print("MISSING BIKE CARD")
        }
    }

    func testPlanBuilder() {
        XCTAssertTrue(tapButton("Scenic"))
        sleep(6)
        attach("30-plan-builder")
        dump("PLAN_BUILDER")

        // Keep the paved surface: it lets the planner fall back to MapKit
        // loops when the OSM Overpass mirrors are slow.
        app.swipeUp()
        sleep(1)
        _ = tapButton("Relaxed", timeout: 3)
        _ = tapButton("Compact", timeout: 3)
        // Metric shows a 16 km chip for the 10-mile preset; imperial shows 10.
        if app.buttons["16"].firstMatch.exists {
            app.buttons["16"].firstMatch.tap()
        } else if app.buttons["10"].firstMatch.exists {
            app.buttons["10"].firstMatch.tap()
        }
        sleep(1)
        attach("31-plan-shape")

        if app.staticTexts["Options"].firstMatch.exists {
            app.staticTexts["Options"].firstMatch.tap()
            sleep(1)
            attach("32-plan-options")
        }

        if app.buttons["Drop start pin"].firstMatch.exists {
            app.buttons["Drop start pin"].firstMatch.tap()
            sleep(2)
            attach("33-plan-pin")
        }

        let find = app.buttons["Find scenic loops"].firstMatch
        let update = app.buttons["Update loops"].firstMatch
        if find.exists {
            find.tap()
        } else if update.exists {
            update.tap()
        } else {
            print("MISSING FIND LOOPS BUTTON")
        }

        let done = waitForAny([
            app.staticTexts["Routes"].firstMatch,
            app.buttons["Preview"].firstMatch,
            app.staticTexts["Couldn't build a loop"].firstMatch,
            app.staticTexts["Routes ready"].firstMatch
        ], timeout: 50)
        print("PLAN FINISHED: \(done)")
        // Results are inserted below the current scroll position; bring them up.
        _ = scroll(to: "Routes", maxSwipes: 6)
        sleep(1)
        attach("34-plan-result")
        dump("PLAN_RESULT")

        if app.buttons["Preview"].firstMatch.exists {
            app.buttons["Preview"].firstMatch.tap()
            sleep(2)
            attach("35-plan-preview")
            dump("PLAN_PREVIEW")
            let close = app.buttons["Close route preview"].firstMatch
            if close.waitForExistence(timeout: 5) {
                // The sheet can still be settling when the preview appears.
                let hittable = NSPredicate(format: "isHittable == true")
                let ready = XCTNSPredicateExpectation(predicate: hittable, object: close)
                _ = XCTWaiter().wait(for: [ready], timeout: 5)
                if close.isHittable { close.tap() } else { print("CLOSE PREVIEW NOT HITTABLE") }
            }
        }
        if app.buttons["Save route"].firstMatch.exists {
            app.buttons["Save route"].firstMatch.tap()
            sleep(1)
            attach("36-plan-saved")
        }
    }

    func testExploreTilesAndSavedPlaces() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        sleep(1)

        let offline = app.staticTexts["Offline data"].firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 5), "Offline tile")
        offline.tap()
        sleep(2)
        attach("60-offline")
        dump("OFFLINE")
        XCTAssertTrue(waitForAny([app.staticTexts["OFFLINE RIDING"].firstMatch], timeout: 8))
        XCTAssertTrue(tapButton("Done", timeout: 5), "Close offline sheet")

        _ = scroll(to: "Saved places", maxSwipes: 4)
        let saved = app.staticTexts["Saved places"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "Saved places tile")
        saved.tap()
        sleep(2)
        attach("61-saved-places")
        dump("SAVED_PLACES")
        if app.buttons["Use my location"].firstMatch.exists {
            app.buttons["Use my location"].firstMatch.tap()
            sleep(1)
            attach("62-saved-places-set")
        }
        if app.buttons["Clear"].firstMatch.exists {
            app.buttons["Clear"].firstMatch.tap()
            sleep(1)
            attach("63-saved-places-cleared")
        }
        _ = tapButton("Done", timeout: 5)

        // Back on the planner: menu arrangement and layout banners.
        if !app.buttons["Arrange"].firstMatch.exists {
            _ = tapButton("Expand ride planner")
        }
        if app.buttons["Arrange"].firstMatch.exists {
            app.buttons["Arrange"].firstMatch.tap()
            sleep(2)
            attach("64-menu-editor")
            if app.buttons["Close menu editor"].firstMatch.exists {
                app.buttons["Close menu editor"].firstMatch.tap()
                sleep(1)
            }
        }

        if app.buttons["Layout"].firstMatch.exists {
            app.buttons["Layout"].firstMatch.tap()
            sleep(1)
            attach("65-layout-editor")
            if app.buttons["Done"].firstMatch.exists {
                app.buttons["Done"].firstMatch.tap()
                sleep(1)
            }
        }
    }

    func testSearchResolveAndRecents() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        sleep(1)
        guard let field = Optional(app.textFields["Search destination"].firstMatch),
              field.waitForExistence(timeout: 5) else {
            XCTFail("Search field missing")
            return
        }
        field.tap()
        field.typeText("Ferry Building")
        sleep(6)
        attach("70-search-suggestions")
        dump("SEARCH_SUGGESTIONS_2")

        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Ferry Building'")).firstMatch
        if suggestion.exists {
            suggestion.tap()
            let routed = waitForAny([app.staticTexts["ROUTE OPTIONS"].firstMatch, app.buttons["Start navigation"].firstMatch], timeout: 30)
            attach("71-suggestion-route")
            print("SUGGESTION ROUTE: \(routed)")
        } else {
            print("NO SUGGESTION BUTTON")
        }

        if app.buttons["Close route preview"].firstMatch.exists {
            app.buttons["Close route preview"].firstMatch.tap()
            sleep(1)
        }
        if app.buttons["Clear destination"].firstMatch.exists {
            app.buttons["Clear destination"].firstMatch.tap()
            sleep(1)
        }
        if !app.textFields["Search destination"].firstMatch.exists {
            _ = tapButton("Expand ride planner")
        }

        // Free-form text: press the keyboard's Search key without choosing a
        // suggestion. The new resolver should still find the place.
        if let free = Optional(app.textFields["Search destination"].firstMatch), free.exists {
            free.tap()
            free.typeText("Coit Tower")
            sleep(2)
            free.typeText("\n")
            let routed = waitForAny([app.staticTexts["ROUTE OPTIONS"].firstMatch, app.buttons["Start navigation"].firstMatch], timeout: 30)
            attach("72-freeform-route")
            print("FREEFORM ROUTE: \(routed)")
        }

        if app.buttons["Close route preview"].firstMatch.exists {
            app.buttons["Close route preview"].firstMatch.tap()
            sleep(1)
        }
        if !app.textFields["Search destination"].firstMatch.exists && !app.textFields["Where to?"].firstMatch.exists {
            _ = tapButton("Expand ride planner")
        }
        attach("73-recents")
        dump("RECENTS")
        let recent = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ferry'")).firstMatch
        if recent.exists {
            recent.tap()
            sleep(3)
            attach("74-recent-route")
        }
    }

    func testRecentsOnly() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        sleep(1)
        let field = app.textFields["Search destination"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Ferry Building")
        sleep(6)
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Ferry Building'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 6), "Suggestion")
        suggestion.tap()
        sleep(2)
        let routed = waitForAny([app.staticTexts["ROUTE OPTIONS"].firstMatch], timeout: 30)
        attach("80-suggestion-route")
        print("ROUTED: \(routed)")
        if app.buttons["Close route preview"].firstMatch.exists {
            app.buttons["Close route preview"].firstMatch.tap()
            sleep(2)
        }
        // The planner stays expanded; scroll down to the recent list.
        _ = scroll(to: "Recent destinations", maxSwipes: 4)
        attach("81-recents")
        dump("RECENTS_ONLY")
        let recent = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ferry Building'")).firstMatch
        if recent.exists {
            recent.tap()
            sleep(3)
            attach("82-recent-route")
        } else {
            print("NO RECENT ROW")
        }
    }

    func testCloseResultsCleanly() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        let field = app.textFields["Search destination"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Ferry Building")
        sleep(6)
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Ferry Building'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 6))
        suggestion.tap()
        XCTAssertTrue(waitForAny([app.staticTexts["ROUTE OPTIONS"].firstMatch], timeout: 30))
        sleep(2)
        attach("90-before-close")
        XCTAssertTrue(tapButton("Close route preview"))
        sleep(5)
        attach("91-after-close")
        dump("AFTER_CLOSE")
        print("ROUTE OPTIONS STILL EXISTS: \(app.staticTexts["ROUTE OPTIONS"].firstMatch.exists)")
        let expandedField = app.textFields["Search destination"].firstMatch
        let compactField = app.textFields["Where to?"].firstMatch
        print("EXPANDED FIELD: \(expandedField.exists), COMPACT FIELD: \(compactField.exists)")
    }

    func testFreeformPreview() {
        XCTAssertTrue(tapButton("Expand ride planner"))
        let field = app.textFields["Search destination"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Coit Tower")
        sleep(3)
        field.typeText("\n")
        let routed = waitForAny([app.staticTexts["ROUTE OPTIONS"].firstMatch], timeout: 30)
        attach("75-freeform-route")
        dump("FREEFORM")
        print("FREEFORM ROUTED: \(routed)")
        XCTAssertTrue(routed)
    }

    func testNavigationBannerLayout() {
        XCTAssertTrue(tapButton("Home"))
        XCTAssertTrue(tapButton("Expand ride planner"))
        XCTAssertTrue(tapButton("Preview route", timeout: 5))
        XCTAssertTrue(waitForAny([app.buttons["Start navigation"].firstMatch], timeout: 30))
        XCTAssertTrue(tapButton("Start navigation"))
        sleep(3)
        attach("95-ride-with-route")
        XCTAssertTrue(tapButton("Close ride screen", timeout: 5))
        sleep(3)
        attach("96-home-with-nav-banner")
        dump("HOME_NAV")
    }
}

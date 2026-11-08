import XCTest

/// A scripted "ride along" audit: it walks the app the way a rider would,
/// captures a screenshot at every screen, and records what is missing instead
/// of stopping at the first problem. Run it with a simulated moving location
/// so the ride-recording path is exercised for real.
final class RiderAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-skipOnboarding"
        ]
        app.launch()

        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow",
                          "Change to Always Allow", "OK", "Don’t Allow", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    // Prefer allowing; the audit needs GPS and motion.
                    if label == "Don’t Allow" || label == "Don't Allow" { continue }
                    button.tap()
                    return true
                }
            }
            return false
        }

        // Location, motion and notification prompts arrive just after launch.
        sleep(5)
        app.tap()
        sleep(2)
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            app.terminate()
        }
    }

    func test10_Onboarding() {
        app.terminate()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-resetOnboarding"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Find the bends."].waitForExistence(timeout: 15),
                      "First run should explain the app before asking for location")
        shot("onboarding")
        XCTAssertTrue(app.buttons["Not now"].exists)
        app.buttons["Not now"].tap()

        let homeReady = app.textFields["Where to?"].waitForExistence(timeout: 10)
            || app.buttons["Ride"].exists
        XCTAssertTrue(homeReady,
                      "Not now should land on the map, not trap the rider")
        XCTAssertFalse(app.staticTexts["Find the bends."].exists)
        shot("onboarding-dismissed")

        app.terminate()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-skipOnboarding"
        ]
        app.launch()
        XCTAssertFalse(app.staticTexts["Find the bends."].waitForExistence(timeout: 5),
                       "Onboarding must not reappear after completion")
    }

    func test11_AboutAndSearch() {
        XCTAssertTrue(tap("Ride menu"))
        XCTAssertTrue(tap("App settings"))
        sleep(1)

        // Garage search lives in Settings.
        if scrollTo("Garage, fuel range & maintenance", maxSwipes: 6),
           tap("Garage, fuel range & maintenance") {
            sleep(1)
            let garageSearch = app.textFields["Search the garage"].firstMatch
            if garageSearch.waitForExistence(timeout: 5) {
                garageSearch.tap()
                garageSearch.typeText("zzzz")
                let noBike = app.staticTexts.containing(
                    NSPredicate(format: "label CONTAINS %@", "No bike matches")
                ).firstMatch
                XCTAssertTrue(noBike.waitForExistence(timeout: 4))
                shot("garage-search-empty")
            } else {
                note("Garage search skipped (empty garage)")
            }
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
        }

        // About / privacy / diagnostics.
        if scrollTo("About, privacy & diagnostics", maxSwipes: 8) {
            XCTAssertTrue(tap("About, privacy & diagnostics"))
            sleep(1)
            shot("about-rider")
            XCTAssertTrue(app.staticTexts["Data sources"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Privacy"].exists)
            XCTAssertTrue(app.staticTexts["Diagnostics"].exists)
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
        } else {
            XCTFail("About & diagnostics is not reachable from Settings")
        }

        // Close Settings and confirm the map is usable again.
        let settingsDone = app.navigationBars["Settings"].buttons["Done"]
        if settingsDone.waitForExistence(timeout: 3) {
            settingsDone.tap()
            sleep(2)
        } else {
            app.swipeDown()
            sleep(2)
        }
        XCTAssertTrue(app.buttons["Ride menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Settings"].exists)
    }

    func test13_OfflineCancel() {
        XCTAssertTrue(tap("Ride menu"))
        XCTAssertTrue(tap("App settings"))
        sleep(1)
        guard scrollTo("Offline riding data", maxSwipes: 8) else {
            XCTFail("Offline riding data is not reachable")
            return
        }
        XCTAssertTrue(tap("Offline riding data"))
        sleep(1)
        shot("offline-data")

        let download = app.buttons["Download around my location"].firstMatch
        guard download.waitForExistence(timeout: 5) else {
            note("Offline download skipped (no saved area state)")
            return
        }
        download.tap()
        sleep(2)
        let cancel = app.buttons["Cancel download"].firstMatch
        if cancel.waitForExistence(timeout: 5) {
            shot("offline-downloading")
            cancel.tap()
            sleep(1)
            XCTAssertTrue(app.staticTexts["Download canceled."].waitForExistence(timeout: 5))
            shot("offline-canceled")
        } else {
            // In this environment Overpass fails/returns almost immediately,
            // so the progress card can disappear before Cancel is tappable.
            note("Offline download ended before Cancel could be shown")
        }
    }

    func test14_AccessibilityTextSize() {
        app.terminate()
        app.launchArguments.append(contentsOf: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraLarge"
        ])
        app.launch()
        sleep(3)
        shot("ax-home")
        XCTAssertTrue(tap("Ride menu"))
        XCTAssertTrue(tap("App settings"))
        sleep(2)
        shot("ax-settings-top")
        // The bottom of settings is where fixed-size rows used to clip.
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        shot("ax-settings-bottom")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    func test12_HistorySearch() {
        app.terminate()
        app.launchArguments.append("-debugSeedRide")
        app.launch()
        sleep(2)
        if app.buttons["Expand ride planner"].firstMatch.exists {
            app.buttons["Expand ride planner"].firstMatch.tap()
            sleep(1)
        }
        _ = scrollTo("Ride history", maxSwipes: 5)
        XCTAssertTrue(tap("Ride history"))
        sleep(1)
        let rideSearch = app.textFields["Search rides, bikes or dates"].firstMatch
        guard rideSearch.waitForExistence(timeout: 5) else {
            note("History search skipped (empty history)")
            return
        }
        rideSearch.tap()
        rideSearch.typeText("zzzz")
        let noRide = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "No ride matches")
        ).firstMatch
        XCTAssertTrue(noRide.waitForExistence(timeout: 4))
        shot("history-search-empty")
    }

    // MARK: - Helpers

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ text: String) {
        print("AUDIT: \(text)")
    }

    @discardableResult
    private func tap(_ label: String, timeout: TimeInterval = 6, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let button = app.buttons[label].firstMatch
        if button.waitForExistence(timeout: timeout) {
            button.tap()
            sleep(1)
            return true
        }
        let text = app.staticTexts[label].firstMatch
        if text.waitForExistence(timeout: 1) {
            text.tap()
            sleep(1)
            return true
        }
        note("MISSING: \(label) (line \(line))")
        return false
    }

    @discardableResult
    private func toggle(_ label: String, timeout: TimeInterval = 3) -> Bool {
        let element = app.switches[label].firstMatch
        if element.waitForExistence(timeout: timeout) {
            element.tap()
            sleep(1)
            return true
        }
        note("MISSING TOGGLE: \(label)")
        return false
    }

    @discardableResult
    private func scrollTo(_ label: String, maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes {
            let element = app.staticTexts[label].firstMatch
            if element.exists, element.isHittable { return true }
            app.swipeUp()
            sleep(1)
        }
        let exists = app.staticTexts[label].firstMatch.exists
        if !exists { note("COULD NOT SCROLL TO: \(label)") }
        return exists
    }

    private func back(_ name: String? = nil) {
        let button = app.navigationBars.buttons.firstMatch
        if button.exists {
            button.tap()
            sleep(1)
            if let name { shot(name) }
        } else {
            note("NO NAV BACK BUTTON")
        }
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) { return true }
            usleep(300_000)
        }
        return false
    }

    private func dismissKeyboard() {
        if app.keyboards.buttons["Search"].firstMatch.exists {
            app.keyboards.buttons["Search"].firstMatch.tap()
        } else {
            app.tap()
        }
        sleep(1)
    }

    // MARK: - 01: First run, settings, saved places, offline data

    func test01_SettingsSavedPlacesAndOffline() {
        shot("010-home-first-run")
        note("launch state captured")

        XCTAssertTrue(tap("Ride menu"), "Ride menu should open")
        shot("011-ride-menu")
        XCTAssertTrue(tap("App settings"), "App settings should open")
        sleep(2)
        shot("012-settings-top")

        // Units.
        if let metric = Optional(app.switches["Metric (km, km/h, metres)"].firstMatch),
           metric.exists {
            metric.tap(); sleep(1)
            shot("013-metric-on")
            metric.tap(); sleep(1)
            shot("014-metric-off")
        } else {
            note("MISSING METRIC TOGGLE")
        }

        let fuel = app.sliders["Fuel in tank"].firstMatch
        if fuel.waitForExistence(timeout: 4) {
            shot("014b-fuel-card")
            fuel.adjust(toNormalizedSliderPosition: 0.8)
            sleep(1)
        } else {
            note("MISSING FUEL SLIDER")
        }

        // Bike picker.
        if tap("Bike model", timeout: 4) {
            shot("015-bike-picker")
            // Choose any bike row that is not already selected.
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ducati'")).firstMatch
            if row.exists { row.tap(); sleep(1) }
            let search = app.textFields["Search bikes"].firstMatch
            if search.exists {
                search.tap()
                search.typeText("Honda")
                sleep(1)
                shot("016-bike-picker-search")
            }
            _ = tap("Close bike picker", timeout: 4)
        }

        // Garage, empty on a fresh install.
        if tap("Garage, fuel range & maintenance", timeout: 4) {
            sleep(1)
            shot("017-garage-empty")
            back("018-settings-from-garage")
        }

        // Voice picker and previews.
        if scrollTo("Narrator voice", maxSwipes: 2) {
            shot("019-voice-card")
            if app.buttons["Narrator voice"].firstMatch.exists {
                app.buttons["Narrator voice"].firstMatch.tap()
                sleep(1)
                shot("020-voice-menu")
                if app.buttons["System default"].firstMatch.exists {
                    app.buttons["System default"].firstMatch.tap()
                    sleep(1)
                }
            }
            _ = tap("Alert voice", timeout: 3)
            _ = tap("Navigation", timeout: 3)
        }

        // Safety, cornering and speed settings.
        app.swipeUp(); app.swipeUp()
        shot("021-settings-safety")
        let safetyToggles = ["Stop signs", "Traffic lights", "Speed and red-light cameras", "Railroad crossings", "School zones",
                             "Curve warnings", "Over-limit alert", "Unpaved road warning"]
        for label in safetyToggles {
            _ = toggle(label)
        }
        shot("022-settings-safety-toggled")
        for label in safetyToggles {
            _ = toggle(label)
        }

        _ = tap("Relaxed", timeout: 2)
        _ = tap("Sport", timeout: 2)
        _ = tap("+5 mph", timeout: 2)
        _ = tap("+10 mph", timeout: 2)

        app.swipeUp(); app.swipeUp()
        shot("023-settings-audio")
        let audioToggles = ["Spoken alerts", "Spoken turn directions",
                            "Binaural helmet cues", "Handlebar remote / controller"]
        for label in audioToggles { _ = toggle(label) }
        for label in audioToggles { _ = toggle(label) }

        // Saved places.
        if tap("Saved places", timeout: 4) {
            sleep(1)
            shot("024-saved-places-empty")
            if app.buttons["Use my location"].firstMatch.exists {
                app.buttons["Use my location"].firstMatch.tap()
                sleep(2)
                shot("025-saved-place-set")
            }
            if app.buttons["Clear"].firstMatch.exists {
                app.buttons["Clear"].firstMatch.tap()
                sleep(1)
                shot("026-saved-place-cleared")
            }
            if app.buttons["Done"].firstMatch.exists {
                app.buttons["Done"].firstMatch.tap()
                sleep(1)
            } else {
                back()
            }
        }

        // Offline data.
        if scrollTo("Offline riding data", maxSwipes: 3), tap("Offline riding data", timeout: 4) {
            sleep(1)
            shot("027-offline")
            if app.buttons["10 mi"].firstMatch.exists {
                app.buttons["10 mi"].firstMatch.tap()
                sleep(1)
            }
            if app.buttons["Download around my location"].firstMatch.exists {
                app.buttons["Download around my location"].firstMatch.tap()
                sleep(10)
                shot("028-offline-download")
            }
            let deleteButton = app.buttons["Delete downloaded data"].firstMatch
            for _ in 0..<30 where deleteButton.exists && !deleteButton.isEnabled {
                sleep(2)
            }
            if deleteButton.exists {
                deleteButton.tap()
                sleep(1)
                shot("029-offline-delete-confirm")
                if app.buttons["Delete everything"].firstMatch.exists {
                    app.buttons["Delete everything"].firstMatch.tap()
                    sleep(2)
                    shot("030-offline-deleted")
                }
            }
            back("031-settings-bottom")
        }

        if app.buttons["Done"].firstMatch.exists {
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }
        shot("032-home-after-settings")
    }

    // MARK: - 02: Search, route options, navigation and the live cockpit

    func test02_SearchRouteNavigationAndRide() {
        // A saved Home far enough away to produce a real route. Relaunching
        // also proves the app reads persisted places correctly.
        app.terminate()
        app.launchArguments += [
            "-saved.home.lat", "37.7500", "-saved.home.lon", "-122.4500",
            "-saved.work.lat", "37.7955", "-saved.work.lon", "-122.3937"
        ]
        app.launch()
        sleep(5)
        app.tap()
        sleep(2)
        shot("040-home")

        // Home shortcut should preview a route in one tap. With no saved Home
        // it first offers to save the current location.
        if tap("Home", timeout: 6) {
            let savePrompt = app.alerts["Save this place?"]
            if savePrompt.waitForExistence(timeout: 3) {
                shot("040b-save-home-prompt")
                if savePrompt.buttons["Save here"].exists {
                    savePrompt.buttons["Save here"].tap()
                    sleep(2)
                }
            }
            let routed = waitForAny([
                app.staticTexts["ROUTE OPTIONS"].firstMatch,
                app.buttons["Start navigation"].firstMatch
            ], timeout: 45)
            note("HOME SHORTCUT ROUTED: \(routed)")
            shot("041-home-shortcut")
        }

        if !app.staticTexts["ROUTE OPTIONS"].firstMatch.exists {
            // Search with free text, then commit a suggestion.
            if app.buttons["Expand ride planner"].firstMatch.exists {
                app.buttons["Expand ride planner"].firstMatch.tap()
                sleep(1)
            }
            let field = app.textFields["Where to?"].firstMatch.exists
                ? app.textFields["Where to?"].firstMatch
                : app.textFields["Search destination"].firstMatch
            if field.waitForExistence(timeout: 5) {
                field.tap()
                field.typeText("Ferry Building")
                sleep(5)
                shot("042-search-suggestions")
                let suggestion = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] 'Ferry'")
                ).firstMatch
                if suggestion.exists {
                    suggestion.tap()
                    _ = waitForAny([app.staticTexts["ROUTE OPTIONS"].firstMatch], timeout: 30)
                } else {
                    dismissKeyboard()
                    _ = waitForAny([app.staticTexts["ROUTE OPTIONS"].firstMatch], timeout: 30)
                }
                shot("043-route-results")
            }
        }

        if app.staticTexts["ROUTE OPTIONS"].firstMatch.waitForExistence(timeout: 10) {
            shot("044-route-options")
            // Select another option if one is offered.
            let optionB = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Option B'")).firstMatch
            if optionB.exists { optionB.tap(); sleep(1); shot("045-option-b") }

            if app.buttons["Save route"].firstMatch.exists {
                app.buttons["Save route"].firstMatch.tap()
                sleep(1)
                shot("046-route-saved")
            }

            if app.buttons["Start navigation"].firstMatch.exists {
                app.buttons["Start navigation"].firstMatch.tap()
                sleep(4)
                shot("047-ride-screen-with-route")
                XCTAssertTrue(app.buttons["Start ride"].firstMatch.waitForExistence(timeout: 8),
                              "Ride screen should offer Start ride")

                app.buttons["Start ride"].firstMatch.tap()
                sleep(10)
                shot("048-recording")

                if app.buttons["Pause"].firstMatch.exists {
                    app.buttons["Pause"].firstMatch.tap()
                    sleep(2)
                    shot("049-paused")
                    if app.buttons["Resume"].firstMatch.exists {
                        app.buttons["Resume"].firstMatch.tap()
                        sleep(4)
                    }
                }

                _ = tap("Calibrate lean angle", timeout: 2)
                sleep(2)

                // Ride menu: camera modes and map styles.
                if tap("Ride menu", timeout: 4) {
                    shot("050-ride-menu")
                    if app.buttons["Camera: Cockpit. Switch view"].firstMatch.exists {
                        app.buttons["Camera: Cockpit. Switch view"].firstMatch.tap()
                        sleep(1)
                    }
                    if app.buttons["Satellite"].firstMatch.exists {
                        app.buttons["Satellite"].firstMatch.tap()
                        sleep(1)
                        shot("051-ride-satellite")
                    }
                    if app.buttons["OLED muted"].firstMatch.exists {
                        app.buttons["OLED muted"].firstMatch.tap()
                        sleep(1)
                    }
                }

                if app.buttons["Stop"].firstMatch.exists {
                    app.buttons["Stop"].firstMatch.tap()
                    sleep(1)
                    shot("052-stop-confirmation")
                    if app.buttons["Save Ride"].firstMatch.exists {
                        app.buttons["Save Ride"].firstMatch.tap()
                        let summary = app.staticTexts["RIDE SAVED"].firstMatch.waitForExistence(timeout: 20)
                        note("RIDE SUMMARY SHOWN: \(summary)")
                        shot("053-ride-summary")
                        if summary, app.buttons["Done"].firstMatch.exists {
                            app.buttons["Done"].firstMatch.tap()
                            sleep(2)
                            shot("054-home-after-ride")
                        }
                    }
                }
            }
        }

        // History and ride detail. Leaving the ride screen leaves the route
        // results up; close them before reaching the Explore grid.
        if app.buttons["Close route preview"].firstMatch.exists {
            app.buttons["Close route preview"].firstMatch.tap()
            sleep(1)
        }
        if app.buttons["Expand ride planner"].firstMatch.exists {
            app.buttons["Expand ride planner"].firstMatch.tap()
            sleep(1)
        }
        _ = scrollTo("Ride history", maxSwipes: 4)
        if tap("Ride history", timeout: 4) {
            sleep(2)
            shot("055-history")
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'mi' OR label CONTAINS 'km'")).firstMatch
            if row.waitForExistence(timeout: 6) {
                row.tap()
                sleep(4)
                shot("056-ride-detail")
                if app.buttons["play.fill"].firstMatch.exists {
                    app.buttons["play.fill"].firstMatch.tap()
                    sleep(3)
                    shot("057-replay")
                }
                if app.buttons["Lean"].firstMatch.exists {
                    app.buttons["Lean"].firstMatch.tap()
                    sleep(2)
                    shot("058-lean-heatmap")
                }
                if app.buttons["Create a story poster"].firstMatch.exists {
                    app.buttons["Create a story poster"].firstMatch.tap()
                    sleep(2)
                    shot("059-poster-studio")
                    if app.buttons["Sunset pass"].firstMatch.exists {
                        app.buttons["Sunset pass"].firstMatch.tap()
                        sleep(1)
                    }
                    if app.buttons["Render poster"].firstMatch.exists {
                        app.buttons["Render poster"].firstMatch.tap()
                        sleep(6)
                        shot("060-poster-rendered")
                        if app.buttons["Share poster"].firstMatch.exists {
                            app.buttons["Share poster"].firstMatch.tap()
                            sleep(3)
                            shot("061-poster-share-sheet")
                            app.swipeDown()
                            sleep(1)
                        }
                    }
                    if app.buttons["Close poster studio"].firstMatch.exists {
                        app.buttons["Close poster studio"].firstMatch.tap()
                        sleep(1)
                    }
                }
                back("062-back-to-history")
            } else {
                note("NO RIDE ROW — history may be empty")
            }

            if app.buttons["Import GPX"].firstMatch.exists {
                app.buttons["Import GPX"].firstMatch.tap()
                sleep(3)
                shot("063-gpx-importer")
                if app.buttons["Cancel"].firstMatch.exists {
                    app.buttons["Cancel"].firstMatch.tap()
                    sleep(1)
                }
            }
            if app.buttons["Close history"].firstMatch.exists {
                app.buttons["Close history"].firstMatch.tap()
                sleep(1)
            }
        }
        shot("064-home-final")
    }

    // MARK: - 03: Scenic loop planner

    func test03_PlanBuilder() {
        if !app.buttons["Scenic"].firstMatch.exists,
           app.buttons["Expand ride planner"].firstMatch.exists {
            app.buttons["Expand ride planner"].firstMatch.tap()
            sleep(1)
        }
        if !tap("Scenic", timeout: 5) {
            // Fall back to the tile in the Explore grid.
            if app.staticTexts["Plan a ride"].firstMatch.exists {
                app.staticTexts["Plan a ride"].firstMatch.tap()
                sleep(2)
            }
        }
        sleep(2)
        shot("070-plan-top")

        // Ride shape controls.
        _ = tap("Relaxed", timeout: 3)
        _ = tap("Twisty", timeout: 3)
        _ = tap("Max twisty", timeout: 3)
        _ = tap("Compact", timeout: 3)
        _ = tap("Extended", timeout: 3)
        _ = tap("Mixed", timeout: 3)
        _ = tap("ADV", timeout: 3)
        _ = tap("Paved", timeout: 3)
        app.swipeUp()
        sleep(1)
        shot("071-plan-shape")

        // Distance slider and preset.
        let preset = app.buttons["10"].firstMatch.exists ? app.buttons["10"].firstMatch : app.buttons["16"].firstMatch
        if preset.exists { preset.tap(); sleep(1) }

        // Options drawer.
        if app.staticTexts["Options"].firstMatch.exists {
            app.staticTexts["Options"].firstMatch.tap()
            sleep(1)
            shot("072-plan-options")
            _ = toggle("Prioritize mountain passes")
        }

        // Drop a start pin at the crosshair.
        if app.buttons["Drop start pin"].firstMatch.exists {
            app.buttons["Drop start pin"].firstMatch.tap()
            sleep(2)
            shot("073-plan-start-pin")
        }
        // Return to a known-valid start before building.
        if app.buttons["Use my location"].firstMatch.exists {
            app.buttons["Use my location"].firstMatch.tap()
            sleep(1)
        }

        // Inspect Shaping mode, but do not drop random pins: a pin in a
        // building or the bay is a legitimate failure and hides whether the
        // ordinary loop search works.
        if app.buttons["Shaping"].firstMatch.exists {
            app.buttons["Shaping"].firstMatch.tap()
            sleep(1)
            shot("074-plan-shaping-pins")
            if app.buttons["Start"].firstMatch.exists {
                app.buttons["Start"].firstMatch.tap()
                sleep(1)
            }
        }

        // Build.
        let find = app.buttons["Find scenic loops"].firstMatch
        let update = app.buttons["Update loops"].firstMatch
        if find.exists, find.isHittable { find.tap() }
        else if update.exists, update.isHittable { update.tap() }
        else {
            app.swipeUp()
            if app.buttons["Find scenic loops"].firstMatch.exists { app.buttons["Find scenic loops"].firstMatch.tap() }
        }
        sleep(3)
        shot("075-plan-building")

        let finished = waitForAny([
            app.staticTexts["Routes"].firstMatch,
            app.buttons["Preview"].firstMatch,
            app.staticTexts["Couldn't build a loop"].firstMatch,
            app.staticTexts["Routes ready"].firstMatch
        ], timeout: 55)
        note("PLAN FINISHED: \(finished)")
        _ = scrollTo("Routes", maxSwipes: 8)
        sleep(1)
        shot("076-plan-results")

        if app.buttons["Save route"].firstMatch.exists {
            app.buttons["Save route"].firstMatch.tap()
            sleep(1)
            shot("077-plan-result-saved")
        }

        if app.buttons["Preview"].firstMatch.exists {
            app.buttons["Preview"].firstMatch.tap()
            sleep(2)
            shot("078-plan-preview")
            if app.buttons["Close route preview"].firstMatch.exists {
                app.buttons["Close route preview"].firstMatch.tap()
                sleep(1)
            } else {
                back()
            }
        }

        // Saved routes should be visible back on the plan page.
        _ = scrollTo("Saved routes", maxSwipes: 8)
        shot("079-plan-saved-routes")
        if app.buttons["Close plan"].firstMatch.exists {
            app.buttons["Close plan"].firstMatch.tap()
            sleep(1)
        }
        shot("080-home-after-plan")
    }

    // MARK: - 04: Garage, menu editing and map chrome

    func test04_GarageMenuAndChrome() {
        // Garage through settings.
        XCTAssertTrue(tap("Ride menu"))
        XCTAssertTrue(tap("App settings"))
        sleep(1)
        if tap("Garage, fuel range & maintenance", timeout: 5) {
            sleep(1)
            shot("090-garage")
            let add = app.buttons["Add a bike"].firstMatch.exists
                ? app.buttons["Add a bike"].firstMatch
                : app.buttons["Add another bike"].firstMatch
            if add.exists {
                add.tap()
                sleep(2)
                shot("091-bike-editor")
                let nickname = app.textFields["Nickname"].firstMatch
                if nickname.waitForExistence(timeout: 5) {
                    nickname.tap(); nickname.typeText("Audit Bike")
                    let make = app.textFields["Make"].firstMatch
                    make.tap(); make.typeText("Yamaha")
                    let model = app.textFields["Model"].firstMatch
                    model.tap(); model.typeText("MT-07")
                    app.buttons["Save"].firstMatch.tap()
                    sleep(2)
                    shot("092-garage-bike")
                }
            }

            let bikeCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Audit Bike'")).firstMatch
            if bikeCard.waitForExistence(timeout: 5) {
                bikeCard.tap()
                sleep(2)
                shot("093-bike-detail")
                if app.buttons["Log"].firstMatch.exists {
                    app.buttons["Log"].firstMatch.tap()
                    sleep(1)
                    let what = app.textFields["What did you do? (oil, tyres, chain…)"].firstMatch
                    if what.exists {
                        what.tap(); what.typeText("Oil change")
                    }
                    app.buttons["Save"].firstMatch.tap()
                    sleep(2)
                    shot("094-maintenance-log")
                }
                back("095-garage-after-log")
            }

            // Long-press a bike for the context menu.
            let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Audit Bike'")).firstMatch
            if card.exists {
                card.press(forDuration: 1.2)
                sleep(1)
                shot("096-garage-context-menu")
                if app.buttons["Edit"].firstMatch.exists {
                    app.buttons["Edit"].firstMatch.tap()
                    sleep(1)
                    shot("097-garage-edit")
                    app.buttons["Cancel"].firstMatch.tap()
                    sleep(1)
                } else {
                    app.tap()
                }
            }
            back("098-settings-from-garage")
        }

        if app.buttons["Done"].firstMatch.exists {
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }

        // Expand the planner to reach the explore area.
        if app.buttons["Expand ride planner"].firstMatch.exists {
            app.buttons["Expand ride planner"].firstMatch.tap()
            sleep(1)
        }
        shot("099-expanded-planner")

        // Menu arrangement.
        if app.buttons["Arrange"].firstMatch.exists {
            app.buttons["Arrange"].firstMatch.tap()
            sleep(2)
            shot("100-menu-editor")
            if app.buttons["Edit"].firstMatch.exists {
                app.buttons["Edit"].firstMatch.tap()
                sleep(1)
                let firstCell = app.cells.firstMatch
                if firstCell.exists {
                    firstCell.press(forDuration: 1.0, thenDragTo: app.cells.element(boundBy: 2))
                    sleep(1)
                }
                shot("101-menu-editor-editing")
            }
            if app.buttons["Done"].firstMatch.exists {
                app.buttons["Done"].firstMatch.tap()
                sleep(1)
            } else if app.buttons["Close menu editor"].firstMatch.exists {
                app.buttons["Close menu editor"].firstMatch.tap()
                sleep(1)
            }
            shot("102-explore-after-arrange")
        }

        // Layout editor.
        if app.buttons["Layout"].firstMatch.exists {
            app.buttons["Layout"].firstMatch.tap()
            sleep(1)
            shot("103-layout-editor")
            let sheet = app.otherElements.firstMatch
            if sheet.exists {
                sheet.press(forDuration: 0.5, thenDragTo: app.otherElements.element(boundBy: 1))
                sleep(1)
            }
            if app.buttons["Reset"].firstMatch.exists {
                app.buttons["Reset"].firstMatch.tap()
                sleep(1)
            }
            if app.buttons["Done"].firstMatch.exists {
                app.buttons["Done"].firstMatch.tap()
                sleep(1)
            }
            shot("104-layout-reset")
        }

        // Map styles.
        if tap("Ride menu", timeout: 4) {
            if app.buttons["Map style"].firstMatch.exists {
                app.buttons["Map style"].firstMatch.tap()
                sleep(1)
                shot("105-map-style-dialog")
                if app.buttons["Satellite"].firstMatch.exists {
                    app.buttons["Satellite"].firstMatch.tap()
                    sleep(2)
                    shot("106-map-satellite")
                }
                if tap("Ride menu", timeout: 3), app.buttons["Map style"].firstMatch.exists {
                    app.buttons["Map style"].firstMatch.tap()
                    sleep(1)
                    if app.buttons["Standard"].firstMatch.exists {
                        app.buttons["Standard"].firstMatch.tap()
                        sleep(1)
                    }
                }
            }
        }

        // Customize layout through the menu.
        if tap("Ride menu", timeout: 4), app.buttons["Customize layout"].firstMatch.exists {
            app.buttons["Customize layout"].firstMatch.tap()
            sleep(1)
            shot("107-layout-from-menu")
            if app.buttons["Done"].firstMatch.exists {
                app.buttons["Done"].firstMatch.tap()
                sleep(1)
            }
        }
    }
}

extension RiderAuditUITests {
    /// Stress the two layouts the app declares support for, and exercise the
    /// hands-free mic path (permission + failure messaging).
    func test05_LandscapeAndVoice() {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        shot("120-home-landscape")
        if app.buttons["Expand ride planner"].firstMatch.exists {
            app.buttons["Expand ride planner"].firstMatch.tap()
            sleep(2)
            shot("121-planner-landscape")
        }
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        shot("122-home-portrait")

        if app.buttons["Ride"].firstMatch.waitForExistence(timeout: 5) {
            app.buttons["Ride"].firstMatch.tap()
            sleep(3)
            shot("123-ride-ready")
            let mic = app.buttons["Start on-device voice commands"].firstMatch
            if mic.waitForExistence(timeout: 4) {
                mic.tap()
                sleep(5)
                app.tap()
                sleep(2)
                shot("124-voice-state")
            } else {
                note("MISSING VOICE BUTTON")
            }
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(3)
            shot("125-ride-landscape")
            XCUIDevice.shared.orientation = .portrait
            sleep(2)
            if app.buttons["Close ride screen"].firstMatch.exists {
                app.buttons["Close ride screen"].firstMatch.tap()
                sleep(1)
            }
        }
    }
}

extension RiderAuditUITests {
    /// Deterministic settings pass: `-debugSettings` opens the sheet directly
    /// instead of depending on a menu item tap in the automation session.
    func test06_SettingsDeep() {
        app.terminate()
        app.launchArguments += ["-debugSettings"]
        app.launch()
        sleep(5)
        app.tap()
        sleep(2)

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8),
                      "Debug settings sheet should open")
        shot("130-settings-deep-top")

        if scrollTo("Fuel in tank", maxSwipes: 3) {
            shot("131-fuel-card")
            let fuel = app.sliders["Fuel in tank"].firstMatch
            if fuel.exists {
                fuel.adjust(toNormalizedSliderPosition: 0.5)
                sleep(1)
                shot("132-fuel-half")
                fuel.adjust(toNormalizedSliderPosition: 0.8)
                sleep(1)
            }
        } else {
            note("MISSING FUEL SLIDER")
        }

        if scrollTo("Speed and red-light cameras", maxSwipes: 6) {
            shot("133-camera-toggle")
            _ = toggle("Speed and red-light cameras")
            sleep(1)
            _ = toggle("Speed and red-light cameras")
        }

        app.swipeUp()
        app.swipeUp()
        shot("134-settings-lower")

        if tap("Saved places", timeout: 4) {
            sleep(2)
            shot("135-saved-places")
            if app.buttons["Done"].firstMatch.exists {
                app.buttons["Done"].firstMatch.tap()
                sleep(1)
            } else {
                back()
            }
        }

        if tap("Offline riding data", timeout: 4) {
            sleep(2)
            shot("136-offline")
            back()
        }

        if app.buttons["Done"].firstMatch.exists {
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }
        shot("137-home-after-settings-deep")
    }

    /// GPX import is a system document picker; give it time to enumerate
    /// providers before deciding it is blank.
    func test07_GPXImporter() {
        if !app.buttons["Expand ride planner"].firstMatch.exists {
            _ = tap("Ride menu", timeout: 3)
            if app.buttons["App settings"].firstMatch.exists {
                app.buttons["App settings"].firstMatch.tap()
                sleep(1)
                if app.buttons["Done"].firstMatch.exists {
                    app.buttons["Done"].firstMatch.tap()
                    sleep(1)
                }
            }
        }
        if app.buttons["Expand ride planner"].firstMatch.exists {
            app.buttons["Expand ride planner"].firstMatch.tap()
            sleep(1)
        }
        _ = scrollTo("Ride history", maxSwipes: 5)
        if tap("Ride history", timeout: 4) {
            sleep(2)
            if app.buttons["Import GPX"].firstMatch.exists {
                app.buttons["Import GPX"].firstMatch.tap()
                sleep(12)
                shot("140-importer-after-12s")
                if app.buttons["Cancel"].firstMatch.exists {
                    app.buttons["Cancel"].firstMatch.tap()
                } else {
                    app.swipeDown()
                }
                sleep(1)
                shot("141-importer-dismissed")
            }
            if app.buttons["Close history"].firstMatch.exists {
                app.buttons["Close history"].firstMatch.tap()
                sleep(1)
            }
        }
    }
}

extension RiderAuditUITests {
    /// Isolates the Home shortcut so a slow/failed MapKit route is visible
    /// instead of being masked by the search fallback.
    func test08_HomeShortcutDiagnostic() {
        app.terminate()
        app.launchArguments += [
            "-saved.home.lat", "37.7500",
            "-saved.home.lon", "-122.4500"
        ]
        app.launch()
        sleep(6)
        app.tap()
        sleep(2)
        shot("150-home-before-shortcut")

        if !tap("Home", timeout: 6) {
            note("HOME CHIP MISSING")
            return
        }
        let savePrompt = app.alerts["Save this place?"]
        if savePrompt.waitForExistence(timeout: 2) {
            note("HOME SAVED PLACE PROMPT APPEARED (launch args not applied)")
            if savePrompt.buttons["Cancel"].exists { savePrompt.buttons["Cancel"].tap() }
        }

        for step in 0..<6 {
            sleep(5)
            shot("151-home-route-\(step)")
            if app.staticTexts["ROUTE OPTIONS"].firstMatch.exists {
                note("HOME ROUTE READY AFTER \((step + 1) * 5)s")
                break
            }
            if app.staticTexts["You're already there. Pick a destination away from your current spot."].exists {
                note("HOME ROUTE DEGENERATE (already there)")
                break
            }
            if app.buttons["Start navigation"].firstMatch.exists {
                note("HOME START NAVIGATION AFTER \((step + 1) * 5)s")
                break
            }
            let error = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                            "Couldn't get directions", "already there")
            ).firstMatch
            if error.exists {
                note("HOME ROUTE ERROR: \(error.label)")
                break
            }
        }
    }
}

extension RiderAuditUITests {
    /// The compact search field sits near the bottom of the screen. Tapping it
    /// must keep the field and suggestions above the keyboard.
    func test09_CompactSearchFocus() {
        shot("160-home-before-search")
        let field = app.textFields["Where to?"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "Compact search field")
        field.tap()
        sleep(2)
        shot("161-compact-focused")
        let expanded = app.textFields["Search destination"].firstMatch
        if expanded.waitForExistence(timeout: 4) {
            expanded.tap()
            sleep(1)
            expanded.typeText("Ferry")
            sleep(3)
            shot("162-expanded-typing")
        } else {
            field.typeText("Ferry")
            sleep(3)
            shot("162-compact-typing")
        }
    }
}

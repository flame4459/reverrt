import XCTest

/// Phase 0 contract: every screen and primary control has a stable identifier.
///
/// These tests intentionally do not assert on copy. When the UI is redesigned,
/// update `AccessibilityID`/`UITestID` only if the element itself changes.
final class AccessibilityContractUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow",
                          "Don’t Allow", "Don't Allow", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            app.terminate()
        }
    }

    // MARK: - Helpers

    private func launch(_ extra: [String] = [], skipOnboarding: Bool = true) {
        app.terminate()
        var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if skipOnboarding { arguments.append("-skipOnboarding") }
        arguments.append(contentsOf: extra)
        app.launchArguments = arguments
        app.launch()

        // A first-run location alert can sit above the app; dismiss it so the
        // contract tests start from the same place on every machine.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1.5) {
                button.tap()
                break
            }
        }
    }

    private func waitForTitle(_ identifier: String, file: StaticString = #filePath,
                              line: UInt = #line) {
        XCTAssertTrue(app.screenTitle(identifier).waitForExistence(timeout: 10),
                      "Missing screen title identifier \(identifier)",
                      file: file, line: line)
    }

    private func require(_ identifier: String, file: StaticString = #filePath,
                         line: UInt = #line) {
        XCTAssertTrue(app.control(identifier).waitForExistence(timeout: 8),
                      "Missing control identifier \(identifier)",
                      file: file, line: line)
    }

    private func requireAny(_ identifier: String, file: StaticString = #filePath,
                            line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8),
                      "Missing element identifier \(identifier)",
                      file: file, line: line)
    }

    // MARK: - Shell

    func testHomeShellUsesStableIdentifiers() {
        launch(["-debugSeedRide", "-debugGarageSeed"])
        waitForTitle(UITestID.Home.title)

        for tab in [UITestID.TabBar.home, UITestID.TabBar.routes, UITestID.TabBar.ride,
                    UITestID.TabBar.garage, UITestID.TabBar.history] {
            require(tab)
        }

        require(UITestID.Home.planRoute)
        require(UITestID.Home.openCockpit)
        require(UITestID.Home.colorScheme)
        requireAny(UITestID.Home.menu)
        require(UITestID.Home.viewGarage)
        require(UITestID.Home.savedPlaces)
        require(UITestID.Home.viewHistory)
        XCTAssertTrue(app.textFields[UITestID.Home.destination].waitForExistence(timeout: 8),
                      "Home must expose the destination input")

        app.control(UITestID.TabBar.routes).tap()
        waitForTitle(UITestID.Routes.title)
        XCTAssertTrue(app.textFields[UITestID.Routes.destination].waitForExistence(timeout: 8),
                      "Routes must keep an identified destination field")
        require(UITestID.Routes.findRoute)

        app.control(UITestID.TabBar.home).tap()
        waitForTitle(UITestID.Home.title)
    }

    // MARK: - Planning

    func testPlanSheetUsesStableIdentifiers() {
        launch(["-debugPlan"])
        waitForTitle(UITestID.Plan.title)
        require(UITestID.Plan.findLoops)
        require(UITestID.Plan.close)

        app.control(UITestID.Plan.close).tap()
        waitForTitle(UITestID.Routes.title)
    }

    // MARK: - Cockpit

    func testCockpitUsesStableIdentifiers() {
        launch(["-debugTabRide"])
        require(UITestID.Cockpit.start)
        require(UITestID.Cockpit.planRoute)
        require(UITestID.Cockpit.close)
        XCTAssertFalse(app.staticTexts["NO DATA"].exists,
                       "The cockpit should not use a placeholder speed-limit card")

        app.control(UITestID.Cockpit.close).tap()
        waitForTitle(UITestID.Home.title)
    }

    func testRecordingCockpitHasNoDuplicateStats() {
        launch(["-debugHud", "-debugRecord"])
        XCTAssertTrue(app.staticTexts["DISTANCE"].waitForExistence(timeout: 10),
                      "The recording cockpit should show the ride stats")
        XCTAssertTrue(app.staticTexts["CLIMB"].exists)
        XCTAssertTrue(app.staticTexts["PEAK"].exists)
        XCTAssertFalse(app.staticTexts["TIME"].exists,
                       "Elapsed time belongs in the recording chip, not a second stats tile")
        XCTAssertFalse(app.staticTexts["DRIVE"].exists,
                       "The duplicate DRIVE card should stay removed")
        XCTAssertFalse(app.staticTexts["NO DATA"].exists,
                       "The placeholder speed-limit card should stay removed")
    }

    // MARK: - Garage & history

    func testGarageAndHistoryUseStableIdentifiers() {
        launch(["-debugSeedRide", "-debugGarageSeed"])

        app.control(UITestID.TabBar.garage).tap()
        waitForTitle(UITestID.Garage.title)
        // Garage search is intentionally hidden below three vehicles.
        require(UITestID.Garage.add)

        app.control(UITestID.TabBar.history).tap()
        waitForTitle(UITestID.History.title)
        require(UITestID.History.importGPX)
        XCTAssertTrue(app.textFields[UITestID.History.search].waitForExistence(timeout: 8),
                      "History search must be identified")
    }

    // MARK: - Secondary sheets

    func testSecondarySheetsUseStableIdentifiers() {
        launch(["-debugSheetSettings"])
        waitForTitle(UITestID.Settings.title)
        require(UITestID.Settings.done)
        app.control(UITestID.Settings.done).tap()

        launch(["-debugSheetInsights"])
        waitForTitle(UITestID.Insights.title)
        require(UITestID.Insights.close)
        app.control(UITestID.Insights.close).tap()

        launch(["-debugSheetSafety"])
        waitForTitle(UITestID.Safety.title)
        require(UITestID.Safety.close)
        app.control(UITestID.Safety.close).tap()

        launch(["-debugSheetPosters"])
        waitForTitle(UITestID.Posters.title)
        require(UITestID.Posters.close)
    }

    // MARK: - Summary & onboarding

    func testSummaryUsesStableIdentifiers() {
        launch(["-debugSummary"])
        require(UITestID.Summary.done)
        require(UITestID.Summary.close)
    }

    func testOnboardingUsesStableIdentifiers() {
        launch(["-resetOnboarding"], skipOnboarding: false)
        waitForTitle(UITestID.Onboarding.title)
        require(UITestID.Onboarding.primary)
        require(UITestID.Onboarding.skip)

        app.control(UITestID.Onboarding.skip).tap()
        waitForTitle(UITestID.Home.title)
    }
}

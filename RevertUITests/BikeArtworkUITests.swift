import XCTest

/// Visual audit for the per-bike pixel-art sprites: hero card, search results
/// and the artwork thumbnail on the settings row.
final class BikeArtworkUITests: XCTestCase {
    private var app: XCUIApplication!

    private var baseArguments: [String] {
        [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-skipOnboarding",
        ]
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = baseArguments + ["-debugBikePicker"]
        app.launch()
        sleep(3)
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

    /// Types into the picker search field, then dismisses the keyboard so the
    /// rows are tappable again.
    private func search(_ text: String) {
        let field = app.textFields["Search bikes"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "search field missing")
        field.tap()
        // The newline commits the field, which drops the keyboard out of the
        // way of the rows underneath.
        field.typeText(text + "\n")
        sleep(1)
    }

    private func tapRow(_ label: String) {
        let row = app.buttons.containing(.staticText, identifier: label).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "row \(label) missing")
        row.tap()
        sleep(2)
    }

    func testBikeArtworkScreens() throws {
        attach("01-picker-hero")

        let cruiser = app.buttons["Cruiser"].firstMatch
        XCTAssertTrue(cruiser.waitForExistence(timeout: 5), "cruiser chip missing")
        cruiser.tap()
        sleep(1)
        attach("02-category-cruiser")

        search("harley")
        attach("03-cruiser-search")

        let clear = app.buttons["Clear bike search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "clear button missing")
        clear.tap()
        sleep(1)

        let all = app.buttons["All"].firstMatch
        if all.exists {
            all.tap()
            sleep(1)
        }

        search("cbr929")
        tapRow("Honda CBR929RR Fireblade 2000")
        attach("04-selected-hero")

        app.terminate()
        app.launchArguments = baseArguments + ["-debugSettings"]
        app.launch()
        sleep(4)
        attach("05-settings-row")

        let bikeRow = app.buttons.containing(.staticText, identifier: "Bike model").firstMatch
        if bikeRow.waitForExistence(timeout: 8) {
            bikeRow.tap()
            sleep(2)
            attach("06-picker-from-settings")
        } else {
            attach("06-bike-row-missing")
        }
    }
}

import XCTest

/// End-to-end flows against the live Transitous API. Each test saves a screenshot
/// (`$SIMULATOR_HOST_HOME/publit-shots/<name>.png` on CI) for the README and website.
final class PublitUITests: XCTestCase {
    private let timeout: TimeInterval = 45

    override func setUp() {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Location") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
    }

    private func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = env
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Touch the top edge (no controls there) so a pending permission alert is handled,
    /// without tapping into the list like `app.tap()` (screen centre) does.
    private func nudge(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            let dir = URL(fileURLWithPath: home).appendingPathComponent("publit-shots")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    /// F08 German localization: navigation, route planning and long Settings footers.
    func testF08GermanLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launchEnvironment = ["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "plan"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Planen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Von")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Nach")).firstMatch.exists)
        sleep(3)
        snap("de-plan")
        app.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Öffentlicher Verkehr ohne Ablenkung.")).firstMatch.exists)
        snap("de-settings")
        app.buttons["Fertig"].tap()
        app.tabBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["In der Nähe"].waitForExistence(timeout: 5))
        snap("de-nearby")
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.navigationBars["Gespeichert"].waitForExistence(timeout: 5))
        snap("de-saved")
    }

    /// F01 Nearby: live departures around the (simulated) location.
    func testF01NearbyShowsDepartures() {
        let app = launch()
        nudge(app) // lets the interruption monitor handle a permission alert
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["All departures"].firstMatch.waitForExistence(timeout: timeout),
                      "no departure board loaded")
        sleep(1)
        snap("nearby")

        app.buttons["All departures"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        snap("stop")
        app.buttons["Save"].tap()
        app.tabBars.buttons["Saved"].tap()
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Marienplatz'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "saved stop not listed")
    }

    /// F02 Plan and compare: routes on one timeline, map overlay, route detail.
    func testF02PlanCompareAndDetail() {
        let app = launch(["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "plan"])
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 10))
        let routes = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'from Marienplatz'"))
        XCTAssertTrue(routes.firstMatch.waitForExistence(timeout: timeout), "no routes found")
        sleep(1)
        snap("plan")

        app.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["Details of selected route"].waitForExistence(timeout: 10))
        sleep(3) // map tiles
        snap("compare")

        app.buttons["Details of selected route"].tap()
        XCTAssertTrue(app.navigationBars["Route"].waitForExistence(timeout: 10))
        sleep(3)
        snap("detail")
        XCTAssertTrue(app.buttons["Remind me to get off"].firstMatch.exists)
    }

    /// F03 Search and Home: find a stop, set it as Home, plan there with one tap.
    func testF03SetHomeAndPlan() {
        let app = launch(["PUBLIT_TAB": "saved"])
        XCTAssertTrue(app.buttons["Set Home"].waitForExistence(timeout: 10))
        app.buttons["Set Home"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Sendlinger Tor")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sendlinger Tor'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: timeout), "no geocoding result")
        snap("search")
        hit.tap()
        XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 5))
        snap("saved")

        app.tabBars.buttons["Plan"].tap()
        let quick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home'")).firstMatch
        XCTAssertTrue(quick.waitForExistence(timeout: 5), "Home quick destination missing")
    }

    /// F04 Edge: empty and nonsense search input must not crash and must say so.
    func testF04SearchEdgeCases() {
        let app = launch(["PUBLIT_TAB": "saved"])
        app.navigationBars["Saved"].buttons["Add"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("x")
        XCTAssertFalse(app.staticTexts["No matches."].waitForExistence(timeout: 2), "searched with 1 character")
        field.typeText("qzqzqzqzqzqz😀ä")
        XCTAssertTrue(app.staticTexts["No matches."].waitForExistence(timeout: timeout))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
    }

    /// F05 Nearby "Where to now?": routes from the current location, leaving now.
    func testF05GoNowFromNearby() {
        let app = launch()
        nudge(app)
        let whereTo = app.buttons["whereToNow"]
        XCTAssertTrue(whereTo.waitForExistence(timeout: 10))
        whereTo.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Sendlinger Tor")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sendlinger Tor'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: timeout))
        hit.tap()
        let leave = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Leave' OR label == 'Walk all the way'")).firstMatch
        XCTAssertTrue(leave.waitForExistence(timeout: timeout), "no routes from here")
        sleep(2)
        snap("gonow")
    }

    /// F06 Station map opens and shows stations around the location.
    func testF06StationMap() {
        let app = launch()
        nudge(app)
        let mapButton = app.buttons["Station map"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 10))
        mapButton.tap()
        XCTAssertTrue(app.navigationBars["Stations"].waitForExistence(timeout: 10))
        sleep(6) // tiles and stops
        snap("stationmap")
    }

    /// F07 Save a planned route: it appears under Upcoming trips, with ticket links in the details.
    func testF07SaveTripAndTickets() {
        let app = launch(["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "plan"])
        let routes = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'from Marienplatz'"))
        XCTAssertTrue(routes.firstMatch.waitForExistence(timeout: timeout), "no routes found")
        routes.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Route"].waitForExistence(timeout: 10))
        let save = app.buttons["Save trip"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.exists, "Save trip missing")
        save.tap()
        XCTAssertTrue(app.collectionViews.buttons["Saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add ticket for this trip"].exists)
        snap("tripactions")
        app.navigationBars["Route"].buttons.firstMatch.tap()
        app.buttons["Clear destination"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Flughafen München'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "saved trip not under Upcoming")
        snap("trips")
    }
}

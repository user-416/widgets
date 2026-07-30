import XCTest

/// One-shot real-mode E2E for the Strava OAuth flow. Forces fake mode OFF,
/// drives the app to "Connect with Strava", then blocks waiting for the host
/// app to come back into focus after the user completes the Strava login in
/// the `ASWebAuthenticationSession` sheet (XCUITest can't drive that sheet —
/// it runs in a separate process — so the human in front of the simulator
/// does the email/password/Authorize taps).
///
/// Flow (numbered = automated, ✋ = you):
///   1. Reset state, force real mode, launch
///   2. Tap "Or add a custom metric"
///   3. Tap the "Activity" card (Strava)
///   4. Tap "Connect with Strava"
///   ✋ Strava login appears in an ASWebAuthenticationSession sheet
///   ✋ You enter your Strava email + password
///   ✋ You tap "Authorize" on the consent screen
///   5. Sheet dismisses, callback URL fires, app exchanges via worker, lands
///      on the "name + color + Add metric" view
///   6. Test captures screenshot, taps "Add metric", returns to Home
final class Phase3RealStravaE2ETest: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testStravaRealModeConnectAndAddMetric() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--reset-state-for-test",
            "-debug.fakeMode.manualOverride", "off"
        ]
        app.launch()

        // Welcome → Or add a custom metric → Activity card.
        XCTAssertTrue(app.buttons["Or add a custom metric"].waitForExistence(timeout: 5))
        app.buttons["Or add a custom metric"].tap()
        sleep(1)
        attach(app, "phase3-02-gallery")

        let stravaCard = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Activity")).firstMatch
        XCTAssertTrue(stravaCard.waitForExistence(timeout: 3), "Strava 'Activity' card must surface in gallery")
        stravaCard.tap()
        sleep(2)
        attach(app, "phase3-03-strava-intro")

        // Tap the brand "Connect with Strava" button. This triggers
        // ASWebAuthenticationSession; the system shows a confirmation prompt
        // first ("'Widgets' Wants to Use 'strava.com' to Sign In") — we'd
        // need to handle the springboard alert if XCUITest sees it as a
        // separate app, but on the simulator it's usually inline.
        let connect = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Connect with Strava")).firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 3), "Connect with Strava button must exist (real-mode AddStrava view)")
        connect.tap()

        // The system asks "Widgets wants to use strava.com to sign in" — we
        // need to tap Continue. SpringBoard alerts surface as a separate
        // process; XCUITest reaches them via XCUIApplication(bundleIdentifier:).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cont = springboard.buttons["Continue"]
        if cont.waitForExistence(timeout: 5) {
            cont.tap()
        }

        attach(app, "phase3-04-web-sheet-opening")

        // Now block waiting for the user to complete the Strava login + Authorize
        // flow. Success surface: AddStravaMetricFlow advances to the "name + color
        // + Add metric" state, which carries the "Add metric" button. Failure
        // surface: an error toast / inline message in the AddStrava view.
        let addMetric = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Add metric")).firstMatch
        let errorRetry = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Try again")).firstMatch
        let stateMismatchText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Couldn't verify the Strava callback")).firstMatch

        // Up to 5 minutes for human-in-the-loop OAuth.
        let deadline = Date().addingTimeInterval(300)
        var landed = false
        while Date() < deadline {
            if addMetric.exists {
                landed = true
                break
            }
            if errorRetry.exists || stateMismatchText.exists {
                attach(app, "phase3-05-oauth-error")
                XCTFail("OAuth flow surfaced an error — see phase3-05-oauth-error")
                return
            }
            // Sleep briefly to avoid hot-spinning the runner.
            Thread.sleep(forTimeInterval: 1.0)
        }

        guard landed else {
            attach(app, "phase3-05-timed-out")
            XCTFail("Timed out waiting 5 min for the OAuth flow to complete — see phase3-05-timed-out")
            return
        }

        attach(app, "phase3-05-post-oauth")

        // Tap Add metric → land on Home with Strava metric visible.
        addMetric.tap()
        sleep(4)
        attach(app, "phase3-06-home-with-strava-metric")
    }
}

private extension XCTestCase {
    func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

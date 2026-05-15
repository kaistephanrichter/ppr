import XCTest

@MainActor
final class PPRScreenshots: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        app.launch()
    }

    func testScreenshots() throws {
        // Screenshot 1: Onboarding
        let startButton = app.buttons[localizedString(de: "Loslegen", en: "Get Started")]
        if startButton.waitForExistence(timeout: 5) {
            snapshot("01_Onboarding")

            // Felder ausfüllen
            let urlField = app.textFields.firstMatch
            if urlField.waitForExistence(timeout: 3) {
                urlField.tap()
                urlField.typeText("http://192.168.1.100:8000")
            }
            let tokenField = app.secureTextFields.firstMatch
            if tokenField.waitForExistence(timeout: 3) {
                tokenField.tap()
                tokenField.typeText("demo-api-token-12345")
            }

            // Button tippen sobald er aktiv ist
            let enabled = startButton.waitForExistence(timeout: 3)
            if enabled && startButton.isEnabled {
                startButton.tap()
            }
        }

        // Warten bis Tab-Bar erscheint
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            // Onboarding hat nicht dismissed — trotzdem Screenshot machen
            snapshot("02_Capture_Fallback")
            return
        }

        // Screenshot 2: Capture Tab (erster Tab ist aktiv)
        snapshot("02_Capture")

        // Screenshot 3: Dokumente Tab
        let docTab = app.tabBars.buttons.element(boundBy: 1)
        if docTab.waitForExistence(timeout: 5) {
            docTab.tap()
            // Kurz warten bis Liste lädt (Ladeindikator verschwindet oder Liste erscheint)
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
            snapshot("03_Documents")
        }

        // Screenshot 4: Einstellungen Tab
        let settingsTab = app.tabBars.buttons.element(boundBy: 2)
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
            snapshot("04_Settings")
        }
    }

    // MARK: - Helpers

    private func localizedString(de: String, en: String) -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang == "de" ? de : en
    }
}

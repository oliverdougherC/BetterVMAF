import XCTest

final class VMAFUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testComparisonRequiresInputsAndRevealsViewingProfile() throws {
        let app = XCUIApplication()
        app.launch()
        let analyze = app.buttons["analyzeComparison"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        XCTAssertFalse(analyze.isEnabled)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Source · original")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Encode · comparison")).firstMatch.exists)
        let assumptions = app.disclosureTriangles["Viewing assumptions"]
        XCTAssertTrue(assumptions.exists)
        assumptions.click()
        XCTAssertTrue(app.popUpButtons["Viewing profile"].waitForExistence(timeout: 2))
        XCTAssertFalse(analyze.isEnabled)
    }

    @MainActor
    func testBatchMakesQueueLimitsAndRequiredSourceVisible() throws {
        let app = XCUIApplication()
        app.launch()
        let batch = app.descendants(matching: .any).matching(identifier: "tray.full").firstMatch
        XCTAssertTrue(batch.waitForExistence(timeout: 5))
        batch.click()
        XCTAssertTrue(app.buttons["Add encodes…"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Start pending"].isEnabled)
        XCTAssertFalse(app.buttons["Clear"].isEnabled)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1,000,000 retained frame samples")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Shared source")).firstMatch.exists)
    }
}

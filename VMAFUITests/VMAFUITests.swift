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
        XCTAssertTrue(app.buttons["choose-Source · original"].isHittable, app.debugDescription)
        XCTAssertTrue(app.buttons["choose-Encode · comparison"].isHittable, app.debugDescription)
        let assumptions = app.disclosureTriangles["Viewing assumptions"]
        XCTAssertTrue(assumptions.exists)
        assumptions.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "viewingProfilePicker").firstMatch.waitForExistence(timeout: 2), app.debugDescription)
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
        let limits = app.descendants(matching: .any).matching(identifier: "batchResourceLimits").firstMatch
        XCTAssertTrue(limits.exists, app.debugDescription)
        XCTAssertTrue((limits.value as? String)?.contains("1,000,000 retained frame samples") == true, app.debugDescription)
        XCTAssertTrue(app.buttons["choose-Shared source · original"].isHittable, app.debugDescription)
    }
}

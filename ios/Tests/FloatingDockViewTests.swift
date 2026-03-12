import XCTest

@MainActor
final class FloatingDockViewTests: XCTestCase {

    // MARK: - DockTab

    func testDockTabIcons() {
        XCTAssertEqual(DockTab.home.icon, "circle.dotted")
        XCTAssertEqual(DockTab.journal.icon, "book")
        XCTAssertEqual(DockTab.reminders.icon, "bell")
        XCTAssertEqual(DockTab.caregivers.icon, "person.2")
        XCTAssertEqual(DockTab.setup.icon, "gearshape")
    }

    func testDockTabLabels() {
        XCTAssertEqual(DockTab.home.label, "Home")
        XCTAssertEqual(DockTab.journal.label, "Journal")
        XCTAssertEqual(DockTab.reminders.label, "Reminders")
        XCTAssertEqual(DockTab.caregivers.label, "Caregivers")
        XCTAssertEqual(DockTab.setup.label, "Setup")
    }

    func testDockTabIds() {
        XCTAssertEqual(DockTab.home.id, "home")
        XCTAssertEqual(DockTab.setup.id, "setup")
    }

    #if DEBUG
    func testDebugSessionTab() {
        XCTAssertEqual(DockTab.session.icon, "waveform")
        XCTAssertEqual(DockTab.session.label, "Session")
    }
    #endif
}

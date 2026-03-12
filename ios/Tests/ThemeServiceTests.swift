import XCTest
import SwiftUI

@MainActor
final class ThemeServiceTests: XCTestCase {

    func testDefaultTypography() {
        let service = ThemeService()
        XCTAssertEqual(service.titleSize, 28)
        XCTAssertEqual(service.bodySize, 18)
        XCTAssertEqual(service.captionSize, 14)
    }

    func testDefaultAnimation() {
        let service = ThemeService()
        XCTAssertEqual(service.orbPulseSpeed, 2.0)
        XCTAssertEqual(service.transitionDuration, 0.3)
    }

    func testApplyThemeUpdatesTypography() {
        let service = ThemeService()
        let theme: [String: Any] = [
            "typography": [
                "titleSize": 32.0,
                "bodySize": 20.0,
                "captionSize": 12.0
            ]
        ]

        service.applyTheme(theme)

        XCTAssertEqual(service.titleSize, 32)
        XCTAssertEqual(service.bodySize, 20)
        XCTAssertEqual(service.captionSize, 12)
    }

    func testApplyThemeUpdatesAnimation() {
        let service = ThemeService()
        let theme: [String: Any] = [
            "animation": [
                "orbPulseSpeed": 3.5,
                "transitionDuration": 0.5
            ]
        ]

        service.applyTheme(theme)

        XCTAssertEqual(service.orbPulseSpeed, 3.5)
        XCTAssertEqual(service.transitionDuration, 0.5)
    }

    func testApplyThemeUpdatesColors() {
        let service = ThemeService()
        let theme: [String: Any] = [
            "colors": [
                "background": "#000000",
                "primary": "#FF0000"
            ]
        ]

        service.applyTheme(theme)

        let bg = UIColor(service.background)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        bg.getRed(&r, green: &g, blue: &b, alpha: nil)
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)

        let prim = UIColor(service.primary)
        prim.getRed(&r, green: &g, blue: &b, alpha: nil)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testApplyThemePartialUpdate() {
        let service = ThemeService()
        let theme: [String: Any] = [
            "animation": [
                "orbPulseSpeed": 5.0
            ]
        ]

        service.applyTheme(theme)

        XCTAssertEqual(service.orbPulseSpeed, 5.0)
        // transitionDuration unchanged
        XCTAssertEqual(service.transitionDuration, 0.3)
        // Typography unchanged
        XCTAssertEqual(service.titleSize, 28)
    }

    func testApplyThemeEmptyDict() {
        let service = ThemeService()
        service.applyTheme([:])

        // All defaults preserved
        XCTAssertEqual(service.titleSize, 28)
        XCTAssertEqual(service.orbPulseSpeed, 2.0)
    }
}

import XCTest
import SwiftUI

final class ColorHexTests: XCTestCase {

    func testSixDigitHex() {
        let color = Color(hex: "#FF0000")
        let components = color.rgbaComponents
        XCTAssertEqual(components.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(components.green, 0.0, accuracy: 0.01)
        XCTAssertEqual(components.blue, 0.0, accuracy: 0.01)
    }

    func testSixDigitHexWithoutHash() {
        let color = Color(hex: "00FF00")
        let components = color.rgbaComponents
        XCTAssertEqual(components.red, 0.0, accuracy: 0.01)
        XCTAssertEqual(components.green, 1.0, accuracy: 0.01)
        XCTAssertEqual(components.blue, 0.0, accuracy: 0.01)
    }

    func testEightDigitHexWithAlpha() {
        let color = Color(hex: "#0000FF80")
        let components = color.rgbaComponents
        XCTAssertEqual(components.red, 0.0, accuracy: 0.01)
        XCTAssertEqual(components.green, 0.0, accuracy: 0.01)
        XCTAssertEqual(components.blue, 1.0, accuracy: 0.01)
        XCTAssertEqual(components.alpha, 128.0 / 255.0, accuracy: 0.01)
    }

    func testInvalidHexFallsBackToGray() {
        let color = Color(hex: "ZZZ")
        let components = color.rgbaComponents
        XCTAssertEqual(components.red, 0.5, accuracy: 0.01)
        XCTAssertEqual(components.green, 0.5, accuracy: 0.01)
        XCTAssertEqual(components.blue, 0.5, accuracy: 0.01)
    }

    func testThemeColorHex() {
        let color = Color(hex: "#E8A87C")
        let components = color.rgbaComponents
        XCTAssertEqual(components.red, 232.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(components.green, 168.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(components.blue, 124.0 / 255.0, accuracy: 0.01)
    }
}

// Helper to extract RGBA from SwiftUI Color for testing
extension Color {
    var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}

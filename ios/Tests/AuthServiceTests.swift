import XCTest

@MainActor
final class AuthServiceTests: XCTestCase {

    func testRandomNonceStringLength() {
        let nonce16 = AuthService.randomNonceString(length: 16)
        XCTAssertEqual(nonce16.count, 16)

        let nonce32 = AuthService.randomNonceString(length: 32)
        XCTAssertEqual(nonce32.count, 32)

        let nonce64 = AuthService.randomNonceString(length: 64)
        XCTAssertEqual(nonce64.count, 64)
    }

    func testRandomNonceStringUniqueness() {
        let nonce1 = AuthService.randomNonceString()
        let nonce2 = AuthService.randomNonceString()
        XCTAssertNotEqual(nonce1, nonce2)
    }

    func testRandomNonceStringCharacterSet() {
        let nonce = AuthService.randomNonceString(length: 100)
        let allowedChars = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        for char in nonce.unicodeScalars {
            XCTAssertTrue(allowedChars.contains(char), "Unexpected character: \(char)")
        }
    }

    func testSha256ProducesConsistentHash() {
        let hash1 = AuthService.sha256("test-input")
        let hash2 = AuthService.sha256("test-input")
        XCTAssertEqual(hash1, hash2)
    }

    func testSha256ProducesDifferentHashesForDifferentInputs() {
        let hash1 = AuthService.sha256("input-a")
        let hash2 = AuthService.sha256("input-b")
        XCTAssertNotEqual(hash1, hash2)
    }

    func testSha256ProducesHexString() {
        let hash = AuthService.sha256("hello")
        // SHA-256 produces 64 hex characters
        XCTAssertEqual(hash.count, 64)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for char in hash.unicodeScalars {
            XCTAssertTrue(hexChars.contains(char), "Non-hex character: \(char)")
        }
    }
}

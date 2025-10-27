import XCTest
@testable import UserKit

final class UserKitTests: XCTestCase {

    func testConfigureCreatesInstance() throws {
        let instance = UserKit.configure(apiKey: "test-api-key")

        XCTAssertNotNil(instance)
        XCTAssertTrue(UserKit.isInitialized)
    }

    func testConfigureReturnsSharedInstance() throws {
        let instance1 = UserKit.configure(apiKey: "test-api-key")
        let instance2 = UserKit.shared

        XCTAssertTrue(instance1 === instance2)
    }

    func testMultipleConfigureCallsReturnsSameInstance() throws {
        let instance1 = UserKit.configure(apiKey: "test-api-key-1")
        let instance2 = UserKit.configure(apiKey: "test-api-key-2")

        XCTAssertTrue(instance1 === instance2)
    }

    func testConfigureCallsCompletionHandler() throws {
        let expectation = expectation(description: "Completion called")

        UserKit.configure(apiKey: "test-api-key") {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testIsIdentifiedPropertyExists() throws {
        UserKit.configure(apiKey: "test-api-key")
        let instance = UserKit.shared

        let isIdentified = instance.isIdentified

        XCTAssertFalse(isIdentified)
    }

    func testIdentifyMethodExists() throws {
        UserKit.configure(apiKey: "test-api-key")
        let instance = UserKit.shared

        XCTAssertNoThrow(instance.identify(id: "user-1", name: "Test", email: "test@example.com"))
    }

    func testResetMethodExists() throws {
        UserKit.configure(apiKey: "test-api-key")
        let instance = UserKit.shared

        XCTAssertNoThrow(instance.reset())
    }

    func testEnqueueMethodExists() throws {
        UserKit.configure(apiKey: "test-api-key")
        let instance = UserKit.shared

        XCTAssertNoThrow(instance.enqueue(reason: "Support", preferredCallTime: nil))
    }

    func testEnqueueMethodWithNilParameters() throws {
        UserKit.configure(apiKey: "test-api-key")
        let instance = UserKit.shared

        XCTAssertNoThrow(instance.enqueue(reason: nil, preferredCallTime: nil))
    }

    func testLogLevelPropertyCanBeSet() throws {
        UserKit.configure(apiKey: "test-api-key")
        let instance = UserKit.shared

        instance.logLevel = .error

        XCTAssertEqual(instance.logLevel, .error)
    }
}

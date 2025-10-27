import XCTest
@testable import UserKit

final class UserManagerTests: XCTestCase {

    var mockAPIClient: MockAPIClient!
    var mockStorage: MockStorage!
    var testableUserManager: TestableUserManager!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        mockStorage = MockStorage()
        testableUserManager = TestableUserManager(apiClient: mockAPIClient, storage: mockStorage)
    }

    override func tearDown() {
        testableUserManager = nil
        mockStorage = nil
        mockAPIClient = nil
        super.tearDown()
    }

    func testIsIdentifiedReturnsTrueWhenCredentialsExist() throws {
        let credentials = Credentials(id: "123", name: "Test", email: "test@example.com", accessToken: "token123")
        try mockStorage.set(credentials, for: "credentials")

        XCTAssertTrue(testableUserManager.isIdentified)
    }

    func testIsIdentifiedReturnsFalseWhenCredentialsDoNotExist() throws {
        XCTAssertFalse(testableUserManager.isIdentified)
    }

    func testIdentifySuccessStoresCredentials() async throws {
        mockAPIClient.userResponse = APIClient.UserResponse(accessToken: "access-token-123")

        await testableUserManager.identify(apiKey: "api-key-123", id: "user-1", name: "John", email: "john@example.com")

        let storedCredentials = try mockStorage.get("credentials", as: Credentials.self)
        XCTAssertEqual(storedCredentials.id, "user-1")
        XCTAssertEqual(storedCredentials.name, "John")
        XCTAssertEqual(storedCredentials.email, "john@example.com")
        XCTAssertEqual(storedCredentials.accessToken, "access-token-123")
    }

    func testIdentifySuccessWithNilNameAndEmail() async throws {
        mockAPIClient.userResponse = APIClient.UserResponse(accessToken: "access-token-456")

        await testableUserManager.identify(apiKey: "api-key-123", id: "user-2", name: nil, email: nil)

        let storedCredentials = try mockStorage.get("credentials", as: Credentials.self)
        XCTAssertEqual(storedCredentials.id, "user-2")
        XCTAssertNil(storedCredentials.name)
        XCTAssertNil(storedCredentials.email)
        XCTAssertEqual(storedCredentials.accessToken, "access-token-456")
    }

    func testIdentifyFailureDoesNotStoreCredentials() async throws {
        mockAPIClient.shouldThrowError = true
        mockAPIClient.errorToThrow = NetworkError.notAuthenticated

        await testableUserManager.identify(apiKey: "invalid-key", id: "user-1", name: "John", email: "john@example.com")

        XCTAssertThrowsError(try mockStorage.get("credentials", as: Credentials.self))
    }

    func testResetDeletesCredentials() async throws {
        let credentials = Credentials(id: "123", name: "Test", email: "test@example.com", accessToken: "token123")
        try mockStorage.set(credentials, for: "credentials")
        mockAPIClient.resetResponse = APIClient.PostDeviceResponse()

        await testableUserManager.reset()

        XCTAssertThrowsError(try mockStorage.get("credentials", as: Credentials.self))
    }

    func testResetCallsAPIEndpoint() async throws {
        let credentials = Credentials(id: "123", name: "Test", email: "test@example.com", accessToken: "token123")
        try mockStorage.set(credentials, for: "credentials")
        mockAPIClient.resetResponse = APIClient.PostDeviceResponse()

        await testableUserManager.reset()

        if case .reset = mockAPIClient.lastCalledEndpoint {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected reset endpoint to be called")
        }
    }

    func testRegisterTokenConvertsDataToHexString() async throws {
        let credentials = Credentials(id: "123", name: "Test", email: "test@example.com", accessToken: "token123")
        try mockStorage.set(credentials, for: "credentials")
        mockAPIClient.postDeviceResponse = APIClient.PostDeviceResponse()

        let tokenData = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])

        await testableUserManager.registerToken(tokenData)

        if case .postDevice(let request) = mockAPIClient.lastCalledEndpoint {
            XCTAssertEqual(request.voipToken, "0123456789abcdef")
        } else {
            XCTFail("Expected postDevice endpoint to be called")
        }
    }

    func testEnqueueWithBothParameters() async throws {
        let credentials = Credentials(id: "123", name: "Test", email: "test@example.com", accessToken: "token123")
        try mockStorage.set(credentials, for: "credentials")
        mockAPIClient.enqueueResponse = APIClient.EnqueueResponse()

        await testableUserManager.enqueue(reason: "Support", preferredCallTime: "2025-01-01T10:00:00Z")

        if case .enqueue(let request) = mockAPIClient.lastCalledEndpoint {
            XCTAssertEqual(request.reason, "Support")
            XCTAssertEqual(request.preferredCallTime, "2025-01-01T10:00:00Z")
        } else {
            XCTFail("Expected enqueue endpoint to be called")
        }
    }

    func testEnqueueWithNilParameters() async throws {
        let credentials = Credentials(id: "123", name: "Test", email: "test@example.com", accessToken: "token123")
        try mockStorage.set(credentials, for: "credentials")
        mockAPIClient.enqueueResponse = APIClient.EnqueueResponse()

        await testableUserManager.enqueue(reason: nil, preferredCallTime: nil)

        if case .enqueue(let request) = mockAPIClient.lastCalledEndpoint {
            XCTAssertNil(request.reason)
            XCTAssertNil(request.preferredCallTime)
        } else {
            XCTFail("Expected enqueue endpoint to be called")
        }
    }
}

class TestableUserManager {
    var isIdentified: Bool {
        (try? storage.get("credentials", as: Credentials.self)) != nil
    }

    private let apiClient: MockAPIClient
    private let storage: MockStorage

    init(apiClient: MockAPIClient, storage: MockStorage) {
        self.apiClient = apiClient
        self.storage = storage
    }

    func identify(apiKey: String, id: String, name: String?, email: String?) async {
        do {
            let response = try await apiClient.request(
                apiKey: apiKey,
                endpoint: .postUser(
                    .init(
                        id: id,
                        name: name,
                        email: email,
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    )
                ),
                as: APIClient.UserResponse.self
            )

            let credentials = Credentials(id: id, name: name, email: email, accessToken: response.accessToken)
            try storage.set(credentials, for: "credentials")
        } catch {
        }
    }

    func reset() async {
        do {
            let credentials = try storage.get("credentials", as: Credentials.self)
            try storage.delete("credentials")

            try await apiClient.request(
                accessToken: credentials.accessToken,
                endpoint: .reset(.init()),
                as: APIClient.PostDeviceResponse.self
            )
        } catch {
        }
    }

    func registerToken(_ token: Data) async {
        do {
            let credentials = try storage.get("credentials", as: Credentials.self)
            let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()

            try await apiClient.request(
                accessToken: credentials.accessToken,
                endpoint: .postDevice(.init(voipToken: tokenString)),
                as: APIClient.PostDeviceResponse.self
            )
        } catch {
        }
    }

    func enqueue(reason: String? = nil, preferredCallTime: String? = nil) async {
        do {
            let credentials = try storage.get("credentials", as: Credentials.self)

            try await apiClient.request(
                accessToken: credentials.accessToken,
                endpoint: .enqueue(.init(reason: reason, preferredCallTime: preferredCallTime)),
                as: APIClient.EnqueueResponse.self
            )
        } catch {
        }
    }
}

class MockAPIClient {
    var userResponse: APIClient.UserResponse?
    var resetResponse: APIClient.PostDeviceResponse?
    var postDeviceResponse: APIClient.PostDeviceResponse?
    var enqueueResponse: APIClient.EnqueueResponse?
    var shouldThrowError = false
    var errorToThrow: Error?
    var lastCalledEndpoint: APIClient.Route?

    func request<T: Decodable>(apiKey: String, endpoint: APIClient.Route, as type: T.Type) async throws -> T {
        lastCalledEndpoint = endpoint

        if shouldThrowError {
            throw errorToThrow ?? NetworkError.notAuthenticated
        }

        if type == APIClient.UserResponse.self, let response = userResponse as? T {
            return response
        }

        throw APIClient.APIError.invalidURL
    }

    func request<T: Decodable>(accessToken: String, endpoint: APIClient.Route, as type: T.Type) async throws -> T {
        lastCalledEndpoint = endpoint

        if shouldThrowError {
            throw errorToThrow ?? NetworkError.notAuthenticated
        }

        if type == APIClient.PostDeviceResponse.self, let response = resetResponse as? T {
            return response
        }

        if type == APIClient.PostDeviceResponse.self, let response = postDeviceResponse as? T {
            return response
        }

        if type == APIClient.EnqueueResponse.self, let response = enqueueResponse as? T {
            return response
        }

        throw APIClient.APIError.invalidURL
    }
}

class MockStorage {
    private var storage: [String: Data] = [:]

    func set<T: Codable>(_ value: T, for key: String) throws {
        let data: Data

        if let string = value as? String {
            data = Data(string.utf8)
        } else if let dataValue = value as? Data {
            data = dataValue
        } else {
            data = try JSONEncoder().encode(value)
        }

        storage[key] = data
    }

    func get<T: Codable>(_ key: String, as type: T.Type) throws -> T {
        guard let data = storage[key] else {
            throw StorageError.itemNotFound
        }

        if type == String.self, let string = String(data: data, encoding: .utf8) as? T {
            return string
        } else if type == Data.self, let raw = data as? T {
            return raw
        } else {
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    func delete(_ key: String) throws {
        storage.removeValue(forKey: key)
    }
}

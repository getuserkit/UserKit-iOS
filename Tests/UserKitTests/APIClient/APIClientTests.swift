import XCTest
@testable import UserKit

final class APIClientTests: XCTestCase {

    func testConfigurationRouteURL() throws {
        let request = APIClient.ConfigurationRequest()
        let route = APIClient.Route.configuration(request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/configuration")
    }

    func testPostUserRouteURL() throws {
        let request = APIClient.UserRequest(id: "123", name: "Test", email: "test@example.com", appVersion: "1.0")
        let route = APIClient.Route.postUser(request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/users")
    }

    func testPostDeviceRouteURL() throws {
        let request = APIClient.PostDeviceRequest(voipToken: "abc123")
        let route = APIClient.Route.postDevice(request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/devices")
    }

    func testResetRouteURL() throws {
        let request = APIClient.ResetRequest()
        let route = APIClient.Route.reset(request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/resets")
    }

    func testPostSessionRouteURL() throws {
        let request = APIClient.PostSessionRequest()
        let route = APIClient.Route.postSession(request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/calls/sessions/new")
    }

    func testPullTracksRouteURL() throws {
        let request = APIClient.PullTracksRequest(tracks: [])
        let route = APIClient.Route.pullTracks("session-123", request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/calls/sessions/session-123/tracks/new")
    }

    func testPushTracksRouteURL() throws {
        let sessionDesc = APIClient.SessionDescription(sdp: "sdp", type: "offer")
        let request = APIClient.PushTracksRequest(sessionDescription: sessionDesc, tracks: [])
        let route = APIClient.Route.pushTracks("session-456", request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/calls/sessions/session-456/tracks/new")
    }

    func testRenegotiateRouteURL() throws {
        let sessionDesc = APIClient.SessionDescription(sdp: "sdp", type: "offer")
        let request = APIClient.RenegotiateRequest(sessionDescription: sessionDesc)
        let route = APIClient.Route.renegotiate("session-789", request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/calls/sessions/session-789/renegotiate")
    }

    func testAcceptRouteURL() throws {
        let wsURL = URL(string: "wss://example.com/accept")!
        let data = APIClient.AcceptRequest.Data(uuid: "uuid-123")
        let request = APIClient.AcceptRequest(type: "accept", data: data)
        let route = APIClient.Route.accept(wsURL, request)

        XCTAssertEqual(route.url, "https://example.com/accept")
    }

    func testEndRouteURL() throws {
        let wsURL = URL(string: "wss://example.com/end")!
        let data = APIClient.EndRequest.Data(uuid: "uuid-456")
        let request = APIClient.EndRequest(type: "end", data: data)
        let route = APIClient.Route.end(wsURL, request)

        XCTAssertEqual(route.url, "https://example.com/end")
    }

    func testEnqueueRouteURL() throws {
        let request = APIClient.EnqueueRequest(reason: "Support", preferredCallTime: "2025-01-01T10:00:00Z")
        let route = APIClient.Route.enqueue(request)

        XCTAssertEqual(route.url, "https://getuserkit.com/api/v1/entries")
    }

    func testConfigurationRouteMethod() throws {
        let request = APIClient.ConfigurationRequest()
        let route = APIClient.Route.configuration(request)

        XCTAssertEqual(route.method, .get)
    }

    func testPostUserRouteMethod() throws {
        let request = APIClient.UserRequest(id: nil, name: nil, email: nil, appVersion: nil)
        let route = APIClient.Route.postUser(request)

        XCTAssertEqual(route.method, .post)
    }

    func testRenegotiateRouteMethod() throws {
        let sessionDesc = APIClient.SessionDescription(sdp: "sdp", type: "offer")
        let request = APIClient.RenegotiateRequest(sessionDescription: sessionDesc)
        let route = APIClient.Route.renegotiate("session-id", request)

        XCTAssertEqual(route.method, .put)
    }

    func testEnqueueRouteMethod() throws {
        let request = APIClient.EnqueueRequest(reason: nil, preferredCallTime: nil)
        let route = APIClient.Route.enqueue(request)

        XCTAssertEqual(route.method, .post)
    }

    func testConfigurationRouteHasNilBody() throws {
        let request = APIClient.ConfigurationRequest()
        let route = APIClient.Route.configuration(request)

        XCTAssertNil(route.body)
    }

    func testPostUserRouteHasBody() throws {
        let request = APIClient.UserRequest(id: "123", name: "Test", email: "test@example.com", appVersion: "1.0")
        let route = APIClient.Route.postUser(request)

        XCTAssertNotNil(route.body)
    }

    func testPostUserEncoderUsesSnakeCase() throws {
        let request = APIClient.UserRequest(id: "123", name: "Test", email: "test@example.com", appVersion: "1.0")
        let route = APIClient.Route.postUser(request)

        let jsonData = try route.encoder.encode(request)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("app_version"))
        XCTAssertFalse(jsonString.contains("appVersion"))
    }

    func testEnqueueEncoderUsesSnakeCase() throws {
        let request = APIClient.EnqueueRequest(reason: "Support", preferredCallTime: "2025-01-01T10:00:00Z")
        let route = APIClient.Route.enqueue(request)

        let jsonData = try route.encoder.encode(request)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("preferred_call_time"))
        XCTAssertFalse(jsonString.contains("preferredCallTime"))
    }

    func testPullTracksResponseFailedTracks() throws {
        let track1 = APIClient.PullTracksResponse.Track(
            mid: "1",
            trackName: "audio",
            sessionId: "session-1",
            errorCode: "404",
            errorDescription: "Track not found"
        )
        let track2 = APIClient.PullTracksResponse.Track(
            mid: "2",
            trackName: "video",
            sessionId: "session-1",
            errorCode: nil,
            errorDescription: nil
        )
        let response = APIClient.PullTracksResponse(
            requiresImmediateRenegotiation: false,
            tracks: [track1, track2],
            sessionDescription: nil
        )

        let failedTracks = response.failedTracks

        XCTAssertEqual(failedTracks.count, 1)
        XCTAssertEqual(failedTracks[0].trackName, "audio")
        XCTAssertEqual(failedTracks[0].error, "Track not found")
    }

    func testPullTracksResponseSuccessfulTracks() throws {
        let track1 = APIClient.PullTracksResponse.Track(
            mid: "1",
            trackName: "audio",
            sessionId: "session-1",
            errorCode: "404",
            errorDescription: "Track not found"
        )
        let track2 = APIClient.PullTracksResponse.Track(
            mid: "2",
            trackName: "video",
            sessionId: "session-1",
            errorCode: nil,
            errorDescription: nil
        )
        let track3 = APIClient.PullTracksResponse.Track(
            mid: "3",
            trackName: "screen",
            sessionId: "session-1",
            errorCode: nil,
            errorDescription: nil
        )
        let response = APIClient.PullTracksResponse(
            requiresImmediateRenegotiation: false,
            tracks: [track1, track2, track3],
            sessionDescription: nil
        )

        let successfulTracks = response.successfulTracks

        XCTAssertEqual(successfulTracks.count, 2)
        XCTAssertEqual(successfulTracks[0].trackName, "video")
        XCTAssertEqual(successfulTracks[1].trackName, "screen")
    }
}

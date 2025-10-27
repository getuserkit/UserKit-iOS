//
//  APIClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

//let baseURL = "http://localhost:3000"
let baseURL = "https://getuserkit.com"

enum NetworkError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return NSLocalizedString("Unauthorized.", comment: "")
        }
    }
}

actor APIClient {
    
    // MARK: - Properties
    
    private let device: Device
    
    
    // MARK: - Functions
    
    init(device: Device) {
        self.device = device
    }
    
    func request<T: Decodable>(apiKey: String, endpoint: Route, as type: T.Type) async throws -> T {
        let data = try await performRequest(apiKey, endpoint)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    
    @discardableResult
    func request<T: Decodable>(accessToken: String, endpoint: Route, as type: T.Type) async throws -> T {
        let data = try await performRequest(accessToken, endpoint)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    
    private func performRequest(_ token: String, _ route: Route) async throws -> Data {
        guard let url = URL(string: route.url) else {
            throw APIError.invalidURL
        }
        
        let startTime = Date().timeIntervalSince1970
        var request = URLRequest(url: url)
        
        let headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "X-Platform": "iOS",
            "X-Platform-Environment": "SDK",
            "X-Vendor-ID": device.vendorId,
            "X-App-Version": device.appVersion,
            "X-App-Build": device.buildVersionNumber,
            "X-OS-Version": device.osVersion,
            "X-Device-Model": device.model,
            "X-Device-Locale": device.locale,
            "X-Device-Region": device.regionCode,
            "X-Device-Language-Code": device.languageCode,
            "X-Device-Currency-Code": device.currencyCode,
            "X-Device-Currency-Symbol": device.currencySymbol,
            "X-Device-Timezone-Offset": device.secondsFromGMT,
            "X-App-Install-Date": device.appInstalledAtString,
            "X-Radio-Type": device.radioType,
            "X-Device-Interface-Style": device.interfaceStyle,
            "X-SDK-Version": sdkVersion,
            "X-Bundle-ID": device.bundleId,
            "X-Low-Power-Mode": device.isLowPowerModeEnabled,
            "X-Is-Sandbox": device.isSandbox,
            "X-Current-Time": Date().isoString,
        ]
        
        for header in headers {
          request.setValue(
            header.value,
            forHTTPHeaderField: header.key
          )
        }
        
        request.httpMethod = route.method.rawValue
        
        let encoder = route.encoder
        
        if let body = route.body {
            let json = try encoder.encode(body)
            request.httpBody = json
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 401 {
                    throw NetworkError.notAuthenticated
                }
            }
            
            let requestDuration = Date().timeIntervalSince1970 - startTime
            Logger.debug(
                logLevel: .debug,
                scope: .network,
                message: "Request Completed",
                info: [
                    "request": request.debugDescription,
                    "api_key": token,
                    "url": request.url?.absoluteString ?? "unknown",
                    "request_duration": requestDuration
                ]
            )
            
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.debug(
                    logLevel: .debug,
                    scope: .network,
                    message: "Raw JSON Response",
                    info: [
                        "url": request.url?.absoluteString ?? "unknown",
                        "json": jsonString
                    ]
                )
            }
            
            return data
        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .network,
                message: "Request Failed:",
                error: error
            )

            throw error
        }
    }
    
    // Model types and request structure from original code
    enum Route: Equatable {
        enum Method: String {
            case get, post, put, delete
        }
        
        case configuration(ConfigurationRequest)
        case postUser(UserRequest)
        case postDevice(PostDeviceRequest)
        case reset(ResetRequest)
        case postSession(PostSessionRequest)
        case pullTracks(String, PullTracksRequest)
        case pushTracks(String, PushTracksRequest)
        case renegotiate(String, RenegotiateRequest)
        case accept(URL, AcceptRequest)
        case end(URL, EndRequest)
        case enqueue(EnqueueRequest)
                
        var url: String {
            switch self {
            case .configuration:
                "\(baseURL)/api/v1/configuration"
                
            case .postSession:
                "\(baseURL)/api/v1/calls/sessions/new"
                
            case .postUser:
                "\(baseURL)/api/v1/users"
                
            case .postDevice:
                "\(baseURL)/api/v1/devices"
                
            case .reset:
                "\(baseURL)/api/v1/resets"
                
            case .pullTracks(let sessionId, _):
                "\(baseURL)/api/v1/calls/sessions/\(sessionId)/tracks/new"

            case .pushTracks(let sessionId, _):
                "\(baseURL)/api/v1/calls/sessions/\(sessionId)/tracks/new"
                
            case .renegotiate(let sessionId, _):
                "\(baseURL)/api/v1/calls/sessions/\(sessionId)/renegotiate"

            case .accept(let url, _):
                url.absoluteString.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://")
                
            case .end(let url, _):
                url.absoluteString.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://")
                
            case .enqueue:
                "\(baseURL)/api/v1/entries"
            }
        }
        
        var method: Method {
            switch self {
            case .configuration:
                return .get
            case .postSession, .postUser, .postDevice, .reset, .pullTracks, .pushTracks, .accept, .end:
                return .post
            case .renegotiate:
                return .put
            case .enqueue:
                return .post
            }
        }
        
        var body: Encodable? {
            switch self {
            case .configuration:
                return nil
            case .postSession:
                return nil
            case .postUser(let request):
                return request
            case .postDevice(let request):
                return request
            case .reset:
                return nil
            case .pullTracks(_, let request):
                return request
            case .pushTracks(_, let request):
                return request
            case .renegotiate(_, let request):
                return request
            case .accept(_, let request):
                return request
            case .end(_, let request):
                return request
            case .enqueue(let request):
                return request
            }
        }
        
        var encoder: JSONEncoder {
            let encoder = JSONEncoder()
            
            if case .postUser = self {
                encoder.keyEncodingStrategy = .convertToSnakeCase
            }
            
            if case .postDevice = self {
                encoder.keyEncodingStrategy = .convertToSnakeCase
            }
            
            if case .enqueue = self {
                encoder.keyEncodingStrategy = .convertToSnakeCase
            }
            
            return encoder
        }
    }
    
    enum APIError: Error {
        case invalidURL
        case missingAPIKey
    }
        
    struct ConfigurationRequest: Codable, Equatable {}
    
    struct ConfigurationResponse: Codable, Equatable {
        struct IceServers: Codable, Equatable {
            let urls: [String]
            let username: String?
            let credential: String?
        }
        let iceServers: [IceServers]
    }
    
    struct PostSessionRequest: Codable, Equatable {}
    
    struct PostDeviceRequest: Codable, Equatable {
        let voipToken: String
    }
    
    struct PostDeviceResponse: Codable, Equatable {}
    
    struct ResetRequest: Codable, Equatable {}
    
    struct ResetResponse: Codable, Equatable {}
    
    struct SessionDescription: Codable, Equatable {
        let sdp: String
        let type: String
    }
    
    struct PostSessionResponse: Codable, Equatable {
        let sessionId: String
    }
    
    struct UserRequest: Codable, Equatable {
        let id: String?
        let name: String?
        let email: String?
        let appVersion: String?
    }
    
    struct UserResponse: Codable, Equatable {
        let accessToken: String
    }
    
    struct PullTracksRequest: Codable, Equatable {
        let tracks: [Track]
        
        struct Track: Codable, Equatable {
            let location: String
            let trackName: String
            let sessionId: String
        }
    }
    
    struct EnqueueRequest: Codable, Equatable {
        let reason: String?
        let preferredCallTime: String?
    }
    
    struct PullTracksResponse: Codable, Equatable {
        let requiresImmediateRenegotiation: Bool
        let tracks: [Track]
        let sessionDescription: SessionDescription?
        
        struct Track: Codable, Equatable {
            let mid: String
            let trackName: String
            let sessionId: String
            let errorCode: String?
            let errorDescription: String?
        }
        
        var failedTracks: [(trackName: String, error: String)] {
            return tracks.compactMap { track in
                guard let errorDescription = track.errorDescription else { return nil }
                return (track.trackName, errorDescription)
            }
        }
        
        var successfulTracks: [Track] {
            return tracks.filter { $0.errorCode == nil }
        }
    }
    
    struct PushTracksRequest: Codable, Equatable {
        let sessionDescription: SessionDescription
        let tracks: [Track]
        
        struct Track: Codable, Equatable {
            let location: String
            let trackName: String
            let mid: String
        }
    }
    
    struct PushTracksResponse: Codable, Equatable {
        let requiresImmediateRenegotiation: Bool
        let tracks: [Track]
        let sessionDescription: SessionDescription
        
        struct Track: Codable, Equatable {
            let mid: String
            let trackName: String
        }
    }
    
    struct RenegotiateRequest: Codable, Equatable {
        let sessionDescription: SessionDescription
    }
    
    struct RenegotiateResponse: Codable, Equatable {}

    struct AcceptRequest: Codable, Equatable {
        let type: String
        let data: Data
        
        struct Data: Codable, Equatable {
            let uuid: String
        }
    }
    
    struct AcceptResponse: Codable, Equatable {}
    
    struct EndRequest: Codable, Equatable {
        let type: String
        let data: Data
        
        struct Data: Codable, Equatable {
            let uuid: String
        }
    }
    
    struct EndResponse: Codable, Equatable {}
    struct EnqueueResponse: Codable, Equatable {}
}

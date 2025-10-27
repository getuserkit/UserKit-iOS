//
//  UserManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation

class UserManager {

    // MARK: - Properties
    
    var isIdentified: Bool {
        (try? storage.get("credentials", as: Credentials.self)) != nil
    }
    
    private let apiClient: APIClient
    
    private let storage: Storage
                
    // MARK: - Functions
    
    init(apiClient: APIClient, storage: Storage) {
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
            
            Logger.debug(
                logLevel: .info,
                scope: .core,
                message: "Identified user in with credentials:",
                info: [
                    "id": credentials.id ?? "",
                    "name": credentials.name ?? "",
                    "email": credentials.email ?? "",
                    "accessToken": credentials.accessToken
                ]
            )
        } catch {
            switch error {
            case NetworkError.notAuthenticated:
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to connect to UserKit, please check your API key is valid",
                )

            default:
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to connect to UserKit",
                    error: error
                )
            }
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

            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "Successfully reset"
            )

        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to reset",
                error: error
            )
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

            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "Successfully registered push token with server",
                info: [
                    "token": tokenString
                ]
            )
        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .pushKit,
                message: "Failed to register push token",
                error: error
            )
        }
    }
    
    public func enqueue(reason: String? = nil, preferredCallTime: String? = nil) async {
        do {
            let credentials = try storage.get("credentials", as: Credentials.self)

            try await apiClient.request(
                accessToken: credentials.accessToken,
                endpoint: .enqueue(.init(reason: reason, preferredCallTime: preferredCallTime)),
                as: APIClient.EnqueueResponse.self
            )

            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "Successfully enqueued call",
                info: [
                    "reason": reason ?? "",
                    "preferredCallTime": preferredCallTime ?? ""
                ]
            )
        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .pushKit,
                message: "Failed to enqueue call",
                error: error
            )
        }
    }
}

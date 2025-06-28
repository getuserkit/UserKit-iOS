//
//  UserManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI
import Network

struct Credentials: Codable {
    let apiKey: String
    let id: String?
    let name: String?
    let email: String?
}

class UserManager {

    // MARK: - Types
    
    struct User: Codable {
        let call: Call?
    }
    
    enum State {
        case none
        case some(User)
    }
    
    // MARK: - Properties
    
    var isLoggedIn: Bool {
        storage.get(AppUserCredentials.self) != nil
    }
    
    private let apiClient: APIClient

    private let callManager: CallManager
    
    private let storage: Storage
    
    private let webSocket: WebSocket
    
    private let state: StateSync<State>
    
    // MARK: - Functions
    
    init(apiClient: APIClient, callManager: CallManager, storage: Storage, webSocket: WebSocket) {
        self.apiClient = apiClient
        self.callManager = callManager
        self.storage = storage
        self.webSocket = webSocket
        self.state = .init(.none)
        
        state.onDidMutate = { [weak self] newState, oldState in
            switch newState {
            case .some(let state):
                self?.callManager.update(state: state.call)
            case .none:
                self?.callManager.update(state: nil)
            }
        }
    }
    
    func identify(apiKey: String, id: String?, name: String?, email: String?) async throws {
        enum UserKitError: Error {
            case identityCredentialRequired
        }
        
        if (id?.isEmpty ?? true) && (name?.isEmpty ?? true) && (email?.isEmpty ?? true) {
            throw UserKitError.identityCredentialRequired
        }
        
        let credentials = Credentials(apiKey: apiKey, id: id, name: name, email: email)
        storage.save(credentials, forType: AppUserCredentials.self)
        
        Logger.debug(
            logLevel: .info,
            scope: .core,
            message: "Identified user in with credentials:",
            info: [
                "id": credentials.id ?? "",
                "name": credentials.name ?? "",
                "email": credentials.email ?? ""
            ]
        )

        try await connect()
    }
    
    func connect() async throws {
        guard let credentials = storage.get(AppUserCredentials.self) else {
            Logger.debug(
                logLevel: .warn,
                scope: .core,
                message: "Attempted to connect to UserKit without valid credentials."
            )
            return
        }
        
        do {
            let response = try await apiClient.request(
                apiKey: credentials.apiKey,
                endpoint: .postUser(
                    .init(
                        id: credentials.id,
                        name: credentials.name,
                        email: credentials.email,
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    )
                ),
                as: APIClient.UserResponse.self
            )

            await apiClient.setAccessToken(response.accessToken)

            webSocket.delegate = self
            webSocket.connect(url: response.webSocketUrl, accessToken: response.accessToken)
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
    
    private func handle(message: String) async {
        do {
            guard let data = message.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messageType = json["type"] as? String else {
                Logger.debug(
                    logLevel: .warn,
                    scope: .core,
                    message: "Unknown user message format",
                    info: [
                        "message": message
                    ]
                )
                return
            }
            
            switch messageType {
            case "userState":
                update(state: json)
                
            case "call.ended":
                // TODO: Handle call end
                break
                
            default:
                Logger.debug(
                    logLevel: .warn,
                    scope: .core,
                    message: "Unknown user message type",
                    info: [
                        "message_type": messageType
                    ]
                )
            }
        } catch {
            self.state.mutate { $0 = .none }
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to handle message",
                error: error
            )
        }
    }
    
    private func update(state: [String: Any]) {
        do {
            let state = state["state"] as? [String: Any]
            let data = try JSONSerialization.data(withJSONObject: state ?? [:])
            let user = try JSONDecoder().decode(User.self, from: data)
            self.state.mutate {
                $0 = .some(user)
            }
        } catch {
            self.state.mutate { $0 = .none }
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to update user state",
                error: error
            )
        }
    }
}

extension UserManager: WebSocketConnectionDelegate {
    func webSocketDidConnect(connection: any WebSocketConnection) {
        webSocket.ping(interval: 10)
        
        Logger.debug(
            logLevel: .info,
            scope: .core,
            message: "Connected to UserKit"
        )
        
        callManager.webSocketDidConnect()
    }
    
    func webSocketDidDisconnect(connection: any WebSocketConnection, closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        Logger.debug(
            logLevel: .info,
            scope: .core,
            message: "Disconnected from UserKit"
        )
        
        switch closeCode {
        case .protocolCode(.goingAway):
            Task {
                try await connect()
            }
        default:
            break
        }
    }
    
    func webSocketViabilityDidChange(connection: any WebSocketConnection, isViable: Bool) {}
    
    func webSocketDidAttemptBetterPathMigration(result: Result<any WebSocketConnection, NWError>) {}
    
    func webSocketDidReceiveError(connection: any WebSocketConnection, error: NWError) {}
    
    func webSocketDidReceivePong(connection: any WebSocketConnection) {}
    
    func webSocketDidReceiveMessage(connection: any WebSocketConnection, string: String) {
        Task { await handle(message: string) }
    }
    
    func webSocketDidReceiveMessage(connection: any WebSocketConnection, data: Data) {}
}

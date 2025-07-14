//
//  UserManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import SwiftUI
import Network
import PushKit
import CallKit

struct Credentials: Codable {
    let id: String?
    let name: String?
    let email: String?
    let accessToken: String
}

class UserManager {

    // MARK: - Types
    
    struct App: Codable {
        let iconUrl: URL?
    }
    
    struct User: Codable {
        let app: App?
        let call: Call?
    }
    
    enum State {
        case none
        case some(User)
    }
    
    // MARK: - Properties
    
    var isIdentified: Bool {
        storage.get(AppUserCredentials.self) != nil
    }
    
    private var accessToken: String? {
        storage.get(AppUserCredentials.self)?.accessToken
    }
    
    private let apiClient: APIClient

    private let callKitManager: CallKitManager

    private let callManager: CallManager
    
    private let storage: Storage
    
    private let webSocket: WebSocket
    
    private let pushKitManager: PushKitManager
    
    private let state: StateSync<State>
    
    // MARK: - Functions
    
    init(apiClient: APIClient, callKitManager: CallKitManager, callManager: CallManager, pushKitManager: PushKitManager, storage: Storage, webSocket: WebSocket) {
        self.apiClient = apiClient
        self.callKitManager = callKitManager
        self.callManager = callManager
        self.pushKitManager = pushKitManager
        self.storage = storage
        self.webSocket = webSocket
        self.state = .init(.none)
        
        pushKitManager.delegate = self
        callKitManager.delegate = self
        callManager.delegate = self
        
        state.onDidMutate = { [weak self] newState, oldState in
            switch newState {
            case .some(let state):
                self?.callManager.update(app: state.app)
                self?.callManager.update(call: state.call)
            case .none:
                self?.callManager.update(call: nil)
            }
        }
    }
    
    func configure() {
        if isIdentified {
            pushKitManager.register()
        }
    }
    
    func identify(apiKey: String, id: String?, name: String?, email: String?) async {
        enum UserKitError: Error {
            case identityCredentialRequired
        }
        
        if (id?.isEmpty ?? true) && (name?.isEmpty ?? true) && (email?.isEmpty ?? true) {
            Logger.debug(
                logLevel: .info,
                scope: .core,
                message: "Attempted to identify user without any credentials provided",
                info: [
                    "id": id as Any,
                    "name": name as Any,
                    "email": email as Any
                ]
            )
            return
        }
                        
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
            storage.save(credentials, forType: AppUserCredentials.self)

            pushKitManager.register()
            
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
    
    func connect(call: CallKitManager.Call) async throws {
        guard let credentials = storage.get(AppUserCredentials.self) else {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Attempted to connect to call whilst unidentified"
            )
            
            return
        }
        
        webSocket.delegate = self
        webSocket.connect(url: call.url, accessToken: credentials.accessToken)
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
// TODO                try await connect()
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

// MARK: - PushKitManagerDelegate

extension UserManager: PushKitManagerDelegate {
    func pushKitManager(_ manager: PushKitManager, didReceiveIncomingPush payload: PushKitManager.Payload) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Handling incoming VoIP push",
            info: [
                "payload": payload
            ]
        )
        
        switch payload.call.state {
        case .ringing:
            callKitManager.reportIncomingCall(uuid: payload.call.uuid, url: payload.call.url, caller: payload.call.caller.name, hasVideo: true)
        case .ended:
            Task { await callKitManager.endCall(uuid: payload.call.uuid) }
        }
    }
    
    func pushKitManager(_ manager: PushKitManager, didUpdatePushToken token: Data) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Push token updated, registering with server",
            info: [
                "token": token.map { String(format: "%02.2hhx", $0) }.joined()
            ]
        )
        
        Task {
            await registerPushToken(token)
        }
    }
    
    private func registerPushToken(_ token: Data) async {
        guard let accessToken = accessToken else { return }
        
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        
        do {
            try await apiClient.request(
                accessToken: accessToken,
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
                info: [
                    "token": tokenString
                ],
                error: error
            )
        }
    }
    
    func pushKitManagerDidInvalidatePushTokenFor(_ manager: PushKitManager) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Push token invalidated"
        )
    }
}

// MARK: - CallKitManagerDelegate

extension UserManager: CallKitManagerDelegate {
    func callKitManager(_ manager: CallKitManager, didAnswerCall call: CallKitManager.Call) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "User answered call via CallKit",
            info: [
                "uuid": call.uuid,
                "url": call.url
            ]
        )
        
        Task {
            do {
                try await connect(call: call)
                await callManager.join()
            }
        }
    }
    
    func callKitManager(_ manager: CallKitManager, didEndCall call: CallKitManager.Call) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "User ended call via CallKit",
            info: [
                "uuid": call.uuid,
                "url": call.url
            ]
        )
        
        Task {
            guard let accessToken = accessToken else {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Cannot send call decline request without access token"
                )
                return
            }
            
            do {
                let endRequest = APIClient.EndRequest(
                    type: "call.participant.end",
                    data: APIClient.EndRequest.Data(uuid: call.uuid.uuidString)
                )
                
                try await apiClient.request(
                    accessToken: accessToken,
                    endpoint: .end(call.url, endRequest),
                    as: APIClient.EndResponse.self
                )
                
                Logger.debug(
                    logLevel: .info,
                    scope: .core,
                    message: "Successfully sent call end request",
                    info: [
                        "uuid": call.uuid.uuidString,
                        "url": call.url.absoluteString
                    ]
                )
            } catch {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to send call end request",
                    info: [
                        "uuid": call.uuid.uuidString,
                        "url": call.url.absoluteString
                    ],
                    error: error
                )
            }
        }
    }
}

// MARK: - CallManagerDelegate

extension UserManager: CallManagerDelegate {
    func callManager(_ manager: CallManager, didEndCall uuid: UUID) {
        Task {
            await callKitManager.endCall(uuid: uuid)
        }
    }
}

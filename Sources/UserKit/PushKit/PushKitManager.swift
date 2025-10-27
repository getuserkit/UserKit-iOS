//
//  PushKitManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 7/3/2025.
//

import Foundation
import PushKit

final class PushKitManager: NSObject, @unchecked Sendable {
    
    // MARK: - Types
    
    struct Payload: Codable {
        struct Call: Codable {
            enum State: String, Codable {
                case ringing
                case ended
            }
            let uuid: UUID
            let url: URL
            let state: State
            let caller: Caller
        }
        let call: Call
    }

    // MARK: - Callbacks

    var didReceiveIncomingPush: @Sendable (Payload) -> Void = { _ in }
    var onTokenUpdate: @Sendable (Data) -> Void = { _ in }
    var onTokenInvalidated: @Sendable () -> Void = {}

    // MARK: - Private Properties

    private let pushRegistry: PKPushRegistry
    private let queue: DispatchQueue
    private let options: UserKitOptions

    // MARK: - Init

    init(options: UserKitOptions, queue: DispatchQueue = .main) {
        self.options = options
        self.queue = queue
        self.pushRegistry = PKPushRegistry(queue: queue)
        super.init()

        pushRegistry.delegate = self
    }

    // MARK: - Public Methods

    func register() {
        guard options.pushKit.enabled else {
            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "PushKit disabled, skipping registration"
            )
            return
        }

        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Registering for VoIP push notifications"
        )

        pushRegistry.desiredPushTypes = [.voIP]
    }

    func unregister() {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Unregistering from VoIP push notifications"
        )

        pushRegistry.desiredPushTypes = []
    }
}

// MARK: - PKPushRegistryDelegate

extension PushKitManager: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }

        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Received VoIP push token update",
            info: [
                "token": pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
            ]
        )

        onTokenUpdate(pushCredentials.token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        guard type == .voIP else { return }

        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Received incoming VoIP push",
            info: ["payload": payload.dictionaryPayload]
        )

        do {
            let data = try JSONSerialization.data(withJSONObject: payload.dictionaryPayload)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(Payload.self, from: data)
            didReceiveIncomingPush(payload)
        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .pushKit,
                message: "Failed to decode payload",
                error: error
            )
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }

        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "VoIP push token invalidated"
        )

        onTokenInvalidated()
    }
}

//
//  PushKitManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 7/3/2025.
//

import Foundation
import PushKit

protocol PushKitManagerDelegate: AnyObject {
    func pushKitManager(_ manager: PushKitManager, didReceiveIncomingPush payload: PushKitManager.Payload)
    func pushKitManager(_ manager: PushKitManager, didUpdatePushToken token: Data)
    func pushKitManagerDidInvalidatePushTokenFor(_ manager: PushKitManager)
}

class PushKitManager: NSObject {
    
    // MARK: - Types
    
    struct Payload: Codable {
        struct Call: Codable {
            struct Caller: Codable {
                let name: String
            }
            let uuid: UUID
            let url: URL
            let state: String
            let caller: Caller
        }
        let call: Call
    }
    
    // MARK: - Properties
    
    weak var delegate: PushKitManagerDelegate?
    
    private let pushRegistry: PKPushRegistry
    private let queue: DispatchQueue
    private let options: UserKitOptions
        
    // MARK: - Initialization
    
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
                
        Task { @MainActor in
            self.delegate?.pushKitManager(self, didUpdatePushToken: pushCredentials.token)
        }
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        guard type == .voIP else { return }
        
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Received incoming VoIP push",
            info: [
                "payload": payload.dictionaryPayload
            ]
        )
        
        do {
            let data = try JSONSerialization.data(withJSONObject: payload.dictionaryPayload)
            let decoder = JSONDecoder()
            let parsedPayload = try decoder.decode(Payload.self, from: data)
            
            delegate?.pushKitManager(self, didReceiveIncomingPush: parsedPayload)
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
        
        Task { @MainActor in
            self.delegate?.pushKitManagerDidInvalidatePushTokenFor(self)
        }
    }
}

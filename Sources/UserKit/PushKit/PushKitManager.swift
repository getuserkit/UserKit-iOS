//
//  PushKitManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 7/3/2025.
//

import Foundation
import PushKit

protocol PushKitManagerDelegate: AnyObject {
    func pushKitManager(_ manager: PushKitManager, didReceiveIncomingPush payload: PKPushPayload)
    func pushKitManager(_ manager: PushKitManager, didUpdatePushToken token: Data)
    func pushKitManager(_ manager: PushKitManager, didInvalidatePushToken token: Data)
}

class PushKitManager: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: PushKitManagerDelegate?
    
    private let pushRegistry: PKPushRegistry
    private let queue: DispatchQueue
    
    private(set) var currentToken: Data?
    private(set) var isRegistered: Bool = false
    
    // MARK: - Initialization
    
    init(queue: DispatchQueue = .main) {
        self.queue = queue
        self.pushRegistry = PKPushRegistry(queue: queue)
        super.init()
        
        pushRegistry.delegate = self
    }
    
    // MARK: - Public Methods
    
    func register() {
        guard !isRegistered else {
            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "PushKit already registered for VoIP pushes"
            )
            return
        }
        
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Registering for VoIP push notifications"
        )
        
        pushRegistry.desiredPushTypes = [.voIP]
        isRegistered = true
    }
    
    func unregister() {
        guard isRegistered else {
            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "PushKit not registered, skipping unregister"
            )
            return
        }
        
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "Unregistering from VoIP push notifications"
        )
        
        pushRegistry.desiredPushTypes = []
        isRegistered = false
        currentToken = nil
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
        
        currentToken = pushCredentials.token
        delegate?.pushKitManager(self, didUpdatePushToken: pushCredentials.token)
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
        
        delegate?.pushKitManager(self, didReceiveIncomingPush: payload)
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "VoIP push token invalidated",
            info: [
                "token": currentToken?.map { String(format: "%02.2hhx", $0) }.joined() ?? "unknown"
            ]
        )
        
        if let token = currentToken {
            delegate?.pushKitManager(self, didInvalidatePushToken: token)
        }
        
        currentToken = nil
    }
}
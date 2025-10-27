//
//  CallManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVFoundation
import Foundation
import UIKit

protocol CallManagerDelegate: AnyObject {
    func callManager(_ manager: CallManager, didEndCall uuid: UUID)
}

class CallManager {
        
    // MARK: - Properties
            
    var didEnd: @Sendable (UUID) -> Void = { _ in }
    
    private let apiClient: APIClient
    
    private let storage: Storage
        
    private var call: Call?
            
    // MARK: - Functions
    
    init(apiClient: APIClient, storage: Storage) {
        self.apiClient = apiClient
        self.storage = storage
        self.call = nil
        
        let defaultCenter = NotificationCenter.default
        defaultCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil) { notification in
                if let call = self.call {
                    Task { await self.join(uuid: call.uuid) }
                }
            }
    }
    
    func connect(caller: Caller, uuid: UUID, url: URL) async {
        self.call = Call(apiClient: apiClient, uuid: uuid)
        self.call?.didEnd = didEnd
        
        do {
            let credenitals = try storage.get("credentials", as: Credentials.self)
            try await self.call?.connect(accessToken: credenitals.accessToken, caller: caller, url: url)
        } catch {
            Logger.debug(logLevel: .error, scope: .core, message: "Failed to connect to call", error: error)
        }
    }
    
    func answer(uuid: UUID) async {
        guard let call = call, call.uuid == uuid else {
            Logger.debug(logLevel: .warn, scope: .core, message: "Attempted to answer call that isn't active")
            return
        }
        
        do {
            try await call.answer()
            try await call.join()
        } catch {
            Logger.debug(logLevel: .error, scope: .core, message: "Failed to answer call", error: error)
        }
    }
    
    func join(uuid: UUID) async {
        guard let call = call, call.uuid == uuid else {
            Logger.debug(logLevel: .warn, scope: .core, message: "Attempted to join call that isn't active")
            return
        }
        
        if await UIApplication.shared.applicationState != .active {
            return
        }
        
        do {
            try await call.join()
        } catch {
            Logger.debug(logLevel: .error, scope: .core, message: "Failed to join call", error: error)
        }
    }
    
    func end(uuid: UUID) async {
        guard let call = call else {
            return
        }
                
        defer { self.call = nil }
        
        do {
            try await call.end(uuid: uuid)
        } catch {
            Logger.debug(logLevel: .error, scope: .core, message: "Failed to end call", error: error)
        }
    }
    
    func didActivateAudio(audioSession: AVAudioSession) {
        call?.didActivateAudio(audioSession: audioSession)
    }
    
    func didDeactivateAudio(audioSession: AVAudioSession) {
        call?.didDeactivateAudio(audioSession: audioSession)
    }
}

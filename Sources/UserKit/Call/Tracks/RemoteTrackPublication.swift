//
//  RemoteTrackPublication.swift
//  UserKit
//
//  Created by Peter Nicholls on 12/8/2025.
//

class RemoteTrackPublication: TrackPublication, @unchecked Sendable {
    
    // MARK: - Properties
    
    override var isMuted: Bool { track?.isMuted ?? state.isMuted }

    // MARK: - Functions
    
    func set(subscriptionState: SubscriptionState) async throws {
        guard state.subscriptionState != subscriptionState else { return }
        
        state.mutate { $0.subscriptionState = subscriptionState }
    }
    
    func set(isMuted newValue: Bool) {
        track?.set(muted: newValue)
        
        guard state.isMuted != newValue else { return }
                
        state.mutate({ $0.isMuted = newValue })
        
        muteDidChange?()
    }
}

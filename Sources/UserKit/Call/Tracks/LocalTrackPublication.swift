//
//  LocalTrackPublication.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation

class LocalTrackPublication: TrackPublication, @unchecked Sendable {
    
    // MARK: - Properties
    
    var suspended: Bool = false
    
    // MARK: - Functions
    
    override init(id: String, mid: String? = nil, name: String, kind: Track.Kind, source: Track.Source, participant: Participant) {
        super.init(id: id, mid: mid, name: name, kind: kind, source: source, participant: participant)
    }
    
    func mute() async throws {
        guard let track = track as? LocalTrack else {
            throw UserKitError.invalidState
        }

        try await track.mute()
    }

    func unmute() async throws {
        guard let track = track as? LocalTrack else {
            throw UserKitError.invalidState
        }

        try await track.unmute()
    }
}

extension LocalTrackPublication {
    func suspend() async throws {
        guard !isMuted else { return }
        
        try await mute()
        suspended = true
    }

    func resume() async throws {
        guard suspended else { return }
        
        try await unmute()
        suspended = false
    }
}

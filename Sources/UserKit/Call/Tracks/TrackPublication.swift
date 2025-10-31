//
//  TrackPublication.swift
//  UserKit
//
//  Created by Peter Nicholls on 30/7/2025.
//

import Foundation

class TrackPublication: NSObject, @unchecked Sendable, ObservableObject {
    
    // MARK: - Types
    
    enum SubscriptionState: Equatable {
        case unsubscribed
        case subscribed
    }
    
    struct State: Equatable, Hashable {
        let id: String
        var isMuted: Bool = false
        let kind: Track.Kind
        var mid: String?
        let name: String
        let source: Track.Source
        var subscriptionState: SubscriptionState = .unsubscribed
        var track: Track?
    }
    
    typealias MuteDidChange = @Sendable () -> Void
    
    // MARK: - Properties
    
    var id: String { state.id }
    
    var isMuted: Bool { track?.state.isMuted ?? false }
    
    var kind: Track.Kind { state.kind }
    
    var muteDidChange: MuteDidChange?
        
    var name: String { state.name }
    
    var track: Track? { state.track }
    
    var source: Track.Source { state.source }
    
    var subscriptionState: SubscriptionState { state.subscriptionState }
    
    weak var participant: Participant?
    
    internal let state: StateSync<State>

    // MARK: - Functions
    
    init(id: String, mid: String? = nil, name: String, kind: Track.Kind, source: Track.Source, participant: Participant) {
        self.state = .init(.init(id: id, kind: kind, mid: mid, name: name, source: source))
        self.participant = participant
    }
    
    @discardableResult
    func set(track newValue: Track?) async -> Track? {
        let oldValue = track
        guard track != newValue else { return oldValue }

        oldValue?.muteDidChange = nil

        state.mutate { $0.track = newValue }

        guard let newTrack = newValue else { return oldValue }
        
        muteDidChange?()
        
        guard newTrack is LocalTrack else { return newTrack }

        newTrack.muteDidChange = { [weak self, weak newTrack] in
            guard
                let self,
                let track = newTrack,
                let call = self.participant?.call,
                let sessionId = call.sessionId
            else { return }

            let messageTrack = WebSocketClient.Message.Client.Track(
                id: "\(sessionId)/\(track.mediaTrack.trackId)",
                type: self.source.type,
                state: track.isMuted ? "inactive" : "active"
            )

            try await call.webSocketClient.send(
                message: .init(
                    type: .updateTrack,
                    data: .updateTrack(.init(transceiverSessionId: sessionId, track: messageTrack))
                )
            )

            self.muteDidChange?()
        }

        return oldValue
    }
}

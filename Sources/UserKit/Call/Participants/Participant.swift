//
//  Participant.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation

class Participant: NSObject, @unchecked Sendable {
 
    // MARK: - Types
    
    struct State: Equatable, Hashable, Sendable {
        var trackPublications = [String: TrackPublication]()
        var state: ParticipantState = .none
    }
    
    enum ParticipantState: String, CaseIterable {
        case none
        case answered
        case joined
    }
    
    // MARK: - Properties
    
    let id: String
    
    let firstName: String?
    
    let lastName: String?
    
    weak var call: Call?
    
    var trackPublications: [String: TrackPublication] { state.trackPublications }
    
    var videoTracks: [TrackPublication] {
        state.trackPublications.values.filter { $0.kind == .video }
    }
    
    var participantState: ParticipantState { state.state }
    
    let publishSerialRunner = SerialRunnerActor<LocalTrackPublication?>()
    
    let state: StateSync<State>
    
    var isCameraEnabled: Bool {
        !(getTrackPublication(source: .camera)?.isMuted ?? true)
    }

    var isMicrophoneEnabled: Bool {
        !(getTrackPublication(source: .microphone)?.isMuted ?? true)
    }

    var isScreenShareEnabled: Bool {
        !(getTrackPublication(source: .screenShareVideo)?.isMuted ?? true)
    }
    
    // MARK: - Functions
    
    init(id: String, firstName: String?, lastName: String?, call: Call) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.call = call
        self.state = .init(.init())
    }
    
    func add(publication: TrackPublication) {
        state.mutate { $0.trackPublications[publication.id] = publication }
    }
    
    func getTrackPublication(source: Track.Source) -> TrackPublication? {
        guard source != .unknown else { return nil }
        if let result = state.trackPublications.values.first(where: { $0.source == source }) {
            return result
        }

        if let result = state.trackPublications.values.filter({ $0.source == .unknown }).first(where: {
            (source == .microphone && $0.kind == .audio) ||
                (source == .camera && $0.kind == .video && $0.name != Track.screenShareVideoName) ||
                (source == .screenShareVideo && $0.kind == .video && $0.name == Track.screenShareVideoName) ||
                (source == .screenShareAudio && $0.kind == .audio && $0.name == Track.screenShareVideoName)
        }) {
            return result
        }

        return nil
    }
    
    func set(participantState: ParticipantState) {
        state.mutate({ $0.state = participantState })
    }
}

extension Participant {
    var initials: String {
        let firstInitial = firstName?.first.map { String($0) } ?? ""
        let lastInitial = lastName?.first.map { String($0) } ?? ""
        
        let combined = (firstInitial + lastInitial).uppercased()
        
        if combined.isEmpty {
            return ""
        }
        
        return combined
    }
}

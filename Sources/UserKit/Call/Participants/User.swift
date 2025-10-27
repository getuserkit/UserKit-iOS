//
//  User.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation
import WebRTC

class User: Participant, @unchecked Sendable {
    
    // MARK: - Properties
    
    var localVideoTracks: [LocalTrackPublication] { videoTracks.compactMap { $0 as? LocalTrackPublication } }
    
    var willStart: ((Track) async throws -> Void)?
    
    var didStart: ((Track) async throws -> Void)?
    
    var didStop: ((Track) async throws -> Void)?
    
    // MARK: - Functions
    
    @discardableResult
    func setMicrophone(enabled: Bool) async throws -> LocalTrackPublication? {
        try await set(source: .microphone, enabled: enabled)
    }
    
    @discardableResult
    func setCamera(enabled: Bool) async throws -> LocalTrackPublication? {
        try await set(source: .camera, enabled: enabled)
    }
    
    @discardableResult
    func setScreenShare(enabled: Bool) async throws -> LocalTrackPublication? {
        try await set(source: .screenShareVideo, enabled: enabled)
    }

    @discardableResult
    func publish(track: LocalTrack) async throws -> LocalTrackPublication {
        guard let call = call, let transport = call.transport else {
            throw UserKitError.invalidState
        }
        
        guard track is LocalVideoTrack || track is LocalAudioTrack else {
            throw UserKitError.invalidState
        }

        let transceiverInit = DispatchQueue.userKitWebRTC.sync { RTCRtpTransceiverInit() }
        transceiverInit.direction = .sendOnly

        let transceiver = try await transport.addTransceiver(with: track.mediaTrack, transceiverInit: transceiverInit)
        track.set(rtpSender: transceiver.sender, transceiver: transceiver, transport: transport)
        try await call.transportShouldNegotiate()
                
        let publication = LocalTrackPublication(id: track.mediaTrack.trackId, name: track.mediaTrack.trackId, kind: track.kind, source: track.source, participant: self)
        await publication.set(track: track)

        add(publication: publication)
        
        return publication
    }
        
    func unpublish() async {
        let publications = state.trackPublications.values.compactMap { $0 as? LocalTrackPublication }
        for publication in publications {
            do {
                try await unpublish(publication: publication)
            } catch {
                Logger.debug(logLevel: .error, scope: .core, message: "Failed to unpublish track", info: ["publication": publication], error: error)
            }
        }
    }
    
    func update(participant: WebSocketClient.Message.Server.Call.Participant) async throws {
        func set(track: WebSocketClient.Message.Server.Call.Participant.Track, state: String) async throws {
            guard let call = call, let sessionId = call.sessionId else {
                return
            }
            
            let track = WebSocketClient.Message.Client.Track(
                id: track.id,
                type: track.type.rawValue,
                state: state
            )
                        
            try await call.webSocketClient.send(message: .init(type: .updateTrack, data: .updateTrack(.init(transceiverSessionId: sessionId, track: track))))
        }
        
        for track in participant.tracks {
            switch track.type {
            case .audio:
                do {
                    guard await DeviceManager.ensureDeviceAccess(for: [.audio]) else {
                        try await set(track: track, state: "denied")
                        return
                    }

                    try await setMicrophone(enabled: track.state != .inactive)
                } catch {
                    try await set(track: track, state: "inactive")
                }
            case .video:
                do {
                    switch (track.state, isCameraEnabled) {
                    case (.requested, false):
                        guard await DeviceManager.ensureDeviceAccess(for: [.video]) else {
                            try await set(track: track, state: "denied")
                            return
                        }
                        try await setCamera(enabled: true)
                    case (.inactive, true):
                        try await setCamera(enabled: false)
                    default:
                        break
                    }
                } catch {
                    try await set(track: track, state: "inactive")
                }
            case .screenShare:
                do {
                    switch (track.state, isScreenShareEnabled) {
                    case (.requested, false):
                        try await setScreenShare(enabled: true)
                    case (.inactive, true):
                        try await setScreenShare(enabled: false)
                    default:
                        break
                    }
                } catch {
                    guard let nsError = error as NSError? else {
                        try await set(track: track, state: "inactive")
                    }
                    
                    switch (nsError.domain, nsError.code) {
                    case ("com.apple.ReplayKit.RPRecordingErrorDomain", -5801):
                        try await set(track: track, state: "denied")
                    default:
                        try await set(track: track, state: "inactive")
                    }
                }
            default:
                break
            }
        }
    }
    
    private func unpublish(publication: LocalTrackPublication) async throws {
        guard let call = call else {
            throw UserKitError.invalidState
        }
        
        state.mutate { $0.trackPublications.removeValue(forKey: publication.id) }
        
        guard let track = publication.track as? LocalTrack else {
            return
        }
        
        try await track.stop()
                
        if let transport = call.transport, let sender = track.state.rtpSender {
            try await transport.remove(track: sender)
            try await call.transportShouldNegotiate()
        }
    }
    
    private func set(source: Track.Source, enabled: Bool) async throws -> LocalTrackPublication? {
        try await publishSerialRunner.run {
            guard let _ = self.call else {
                throw UserKitError.invalidState
            }
            
            if let publication = self.getTrackPublication(source: source) as? LocalTrackPublication {
                try await enabled ? publication.unmute() : publication.mute()
                return publication
            }
            
            guard enabled else {
                return nil
            }
                        
            switch source {
            case .camera:
                let localTrack = LocalVideoTrack.createCameraTrack(isMuted: true)
                try await localTrack.start()
                try Task.checkCancellation()
                let publication = try await self.publish(track: localTrack)
                try await publication.unmute()
                return publication
            case .microphone:
                let localTrack = LocalAudioTrack.create(isMuted: true)
                try await localTrack.start()
                try Task.checkCancellation()
                let publication = try await self.publish(track: localTrack)
                try await publication.unmute()
                return publication
            case .screenShareVideo:
                let localTrack = LocalVideoTrack.createInAppScreenShareTrack(isMuted: true)
                localTrack.willStart = { [weak self] in
                    try await self?.willStart?(localTrack)
                }
                localTrack.didStart = { [weak self] in
                    try await self?.didStart?(localTrack)
                }
                localTrack.didStop = { [weak self] in
                    try await self?.didStop?(localTrack)
                }
                try await localTrack.start()
                try Task.checkCancellation()
                let publication = try await self.publish(track: localTrack)
                try await publication.unmute()
                return publication
            default:
                break
            }
            
            return nil
        }
    }
}

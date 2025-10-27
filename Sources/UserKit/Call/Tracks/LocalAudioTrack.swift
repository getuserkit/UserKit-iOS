//
//  LocalAudioTrack.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation
import WebRTC

class LocalAudioTrack: Track, LocalTrack, AudioTrack, @unchecked Sendable {
    
    // MARK: - Properties
    
    // MARK: - Functions
    
    static func create(name: String = Track.microphoneName, isMuted: Bool) -> LocalAudioTrack {
        let constraints: [String: String] = [:]
        let audioConstraints = DispatchQueue.userKitWebRTC.sync {
            RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: constraints)
        }

        let audioSource = RTC.createAudioSource(audioConstraints)
        let rtcTrack = RTC.createAudioTrack(source: audioSource)
        rtcTrack.isEnabled = true

        return LocalAudioTrack(name: name, kind: .audio, source: .microphone, track: rtcTrack, isMuted: isMuted)
    }
    
    override func startCapture() async throws {
        try await unmute()
    }
    
    override func stopCapture() async throws {
        try await mute()
    }
    
    override func mute() async throws {
        try await super.mute()
    }

    override func unmute() async throws {
        try await super.unmute()
    }
}

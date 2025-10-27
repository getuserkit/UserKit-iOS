//
//  RTC.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation
import WebRTC

actor RTC {
    
    // MARK: - Types
    
    struct State {
        var isInitialized: Bool = false
    }

    // MARK: - Properties
    
    static let state = StateSync(State())
    
    static let peerConnectionFactory: RTCPeerConnectionFactory = {
        state.mutate { $0.isInitialized = true }

        RTCInitializeSSL()

        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()
    
    // MARK: - Functions
    
    static func createAudioSource(_ constraints: RTCMediaConstraints?) -> RTCAudioSource {
        DispatchQueue.userKitWebRTC.sync { peerConnectionFactory.audioSource(with: constraints) }
    }
    
    static func createAudioTrack(source: RTCAudioSource) -> RTCAudioTrack {
        DispatchQueue.userKitWebRTC.sync { peerConnectionFactory.audioTrack(with: source, trackId: UUID().uuidString) }
    }
    
    static func createVideoSource(forScreenShare: Bool) -> RTCVideoSource {
        DispatchQueue.userKitWebRTC.sync { peerConnectionFactory.videoSource(forScreenCast: forScreenShare) }
    }
    
    static func createVideoTrack(source: RTCVideoSource) -> RTCVideoTrack {
        DispatchQueue.userKitWebRTC.sync { peerConnectionFactory.videoTrack(with: source, trackId: UUID().uuidString) }
    }
    
    static func createVideoCapturer() -> RTCVideoCapturer {
        DispatchQueue.userKitWebRTC.sync { RTCVideoCapturer() }
    }
}

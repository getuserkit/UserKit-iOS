//
//  LocalVideoTrack.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation
import WebRTC

class LocalVideoTrack: Track, LocalTrack, AudioTrack, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var capturer: VideoCapturer
    
    private var videoSource: RTCVideoSource
    
    // MARK: - Functions

    init(name: String, source: Track.Source, capturer: VideoCapturer, videoSource: RTCVideoSource, isMuted: Bool) {
        let rtcTrack = RTC.createVideoTrack(source: videoSource)
        rtcTrack.isEnabled = !isMuted

        self.capturer = capturer
        self.videoSource = videoSource

        super.init(name: name, kind: .video, source: source, track: rtcTrack, isMuted: isMuted)
    }
    
    override func startCapture() async throws {
        try await capturer.startCapture()
    }
    
    override func stopCapture() async throws {
        try await capturer.stopCapture()
    }
    
    override func mute() async throws {
        try await super.mute()
    }

    override func unmute() async throws {
        try await super.unmute()
    }
}

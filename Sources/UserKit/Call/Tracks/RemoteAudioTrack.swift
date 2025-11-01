//
//  RemoteAudioTrack.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation
import WebRTC

class RemoteAudioTrack: Track, RemoteTrack, AudioTrack, @unchecked Sendable {

    // MARK: - Properties

    // MARK: - Functions

    init(name: String, track: RTCMediaStreamTrack, isMuted: Bool) {
        super.init(name: name, kind: .audio, source: .microphone, track: track, isMuted: isMuted)
    }
}

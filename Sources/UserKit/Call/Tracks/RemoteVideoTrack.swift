//
//  RemoteVideoTrack.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation
import WebRTC

class RemoteVideoTrack: Track, RemoteTrack, @unchecked Sendable {

    // MARK: - Properties

    // MARK: - Functions

    init(name: String, source: Track.Source, track: RTCMediaStreamTrack, isMuted: Bool) {
        super.init(name: name, kind: .video, source: source, track: track, isMuted: isMuted)
    }
}

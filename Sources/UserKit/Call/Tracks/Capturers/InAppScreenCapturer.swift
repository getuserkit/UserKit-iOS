//
//  InAppScreenCapturer.swift
//  UserKit
//
//  Created by Peter Nicholls on 30/7/2025.
//

import Foundation
import ReplayKit
import WebRTC

class InAppScreenCapturer: VideoCapturer, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let capturer = RTC.createVideoCapturer()
    
    private let options: ScreenShareCaptureOptions
    
    // MARK: - Functions

    override init(delegate: RTCVideoCapturerDelegate) {
        self.options = ScreenShareCaptureOptions()
        super.init(delegate: delegate)
    }

    override public func startCapture() async throws -> Bool {
        let didStart = try await super.startCapture()

        guard didStart else { return false }

        try await RPScreenRecorder.shared().startCapture { [weak self] sampleBuffer, type, _ in
            guard let self else { return }
            // Only process .video
            if type == .video {
                capture(sampleBuffer: sampleBuffer, capturer: capturer, options: options)
            }
        }

        return true
    }

    override public func stopCapture() async throws -> Bool {
        let didStop = try await super.stopCapture()

        guard didStop else { return false }

        RPScreenRecorder.shared().stopCapture()

        return true
    }
}

extension LocalVideoTrack {
    static func createInAppScreenShareTrack(name: String = Track.screenShareVideoName, isMuted: Bool) -> LocalVideoTrack {
        let videoSource = RTC.createVideoSource(forScreenShare: true)
        let capturer = InAppScreenCapturer(delegate: videoSource)
        return LocalVideoTrack(name: name, source: .screenShareVideo, capturer: capturer, videoSource: videoSource, isMuted: isMuted)
    }
}

//
//  VideoCapturer.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation
import WebRTC

protocol VideoCapturerProtocol {
    var capturer: RTCVideoCapturer { get }
}

extension VideoCapturerProtocol {
    var capturer: RTCVideoCapturer { fatalError("Must be implemented") }
}

class VideoCapturer: NSObject, @unchecked Sendable, VideoCapturerProtocol {
        
    // MARK: - Properties
    
    private weak var delegate: RTCVideoCapturerDelegate?
            
    static let supportedPixelFormats = DispatchQueue.userKitWebRTC.sync { RTCCVPixelBuffer.supportedPixelFormats() }
    
    // MARK: - Functions
    
    init(delegate: RTCVideoCapturerDelegate) {
        self.delegate = delegate
        
        super.init()
    }
        
    static func createTimeStampNs() -> Int64 {
        let systemTime = ProcessInfo.processInfo.systemUptime
        return Int64(systemTime * Double(NSEC_PER_SEC))
    }
    
    @discardableResult
    func startCapture() async throws -> Bool {
        return true
    }
    
    @discardableResult
    func stopCapture() async throws -> Bool {
        return true
    }
}

extension VideoCapturer {
    func capture(frame: RTCVideoFrame, capturer: RTCVideoCapturer, device: AVCaptureDevice? = nil, options: VideoCaptureOptions) {
        delegate?.capturer(capturer, didCapture: frame)
    }
    
    func capture(pixelBuffer: CVPixelBuffer, capturer: RTCVideoCapturer, timeStampNs: Int64 = VideoCapturer.createTimeStampNs(), rotation: VideoRotation = ._0, options: VideoCaptureOptions) {
        // check if pixel format is supported by WebRTC
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard VideoCapturer.supportedPixelFormats.contains(where: { $0.uint32Value == pixelFormat }) else {
            // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            // kCVPixelFormatType_32BGRA
            // kCVPixelFormatType_32ARGB
            return
        }

        let sourceDimensions = Dimensions(width: Int32(CVPixelBufferGetWidth(pixelBuffer)),
                                          height: Int32(CVPixelBufferGetHeight(pixelBuffer)))

        guard sourceDimensions.isEncodeSafe else {
            return
        }

        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let rtcFrame = RTCVideoFrame(buffer: rtcBuffer, rotation: rotation.toRTCType(), timeStampNs: timeStampNs)

        capture(frame: rtcFrame, capturer: capturer, options: options)
    }
    
    func capture(sampleBuffer: CMSampleBuffer, capturer: RTCVideoCapturer, options: VideoCaptureOptions) {
        guard CMSampleBufferGetNumSamples(sampleBuffer) == 1,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer)
        else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timeStampNs = Int64(CMTimeGetSeconds(timeStamp) * Double(NSEC_PER_SEC))

        capture(pixelBuffer: pixelBuffer, capturer: capturer, timeStampNs: timeStampNs, rotation: ._0, options: options)
    }
}

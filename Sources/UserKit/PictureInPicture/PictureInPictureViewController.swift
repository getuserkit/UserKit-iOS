//
//  PictureInPictureViewController.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit
import UIKit
import SwiftUI
import WebRTC

protocol PictureInPictureViewControllerDelegate: AnyObject {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool
}

final class PictureInPictureViewController: UIViewController {
    
    // MARK: - Properties
        
    weak var delegate: PictureInPictureViewControllerDelegate?
    
    lazy var pictureInPictureController: AVPictureInPictureController = {
        let pictureInPictureController = AVPictureInPictureController(contentSource: pictureInPictureControllerContentSource)
        return pictureInPictureController
    }()
        
    private lazy var pictureInPictureVideoCallViewController: PictureInPictureVideoCallViewController = {
        let pictureInPictureVideoCallViewController = PictureInPictureVideoCallViewController()
        return pictureInPictureVideoCallViewController
    }()

    private lazy var pictureInPictureControllerContentSource: AVPictureInPictureController.ContentSource = {
        let pictureInPictureControllerContentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: view,
            contentViewController: pictureInPictureVideoCallViewController
        )
        return pictureInPictureControllerContentSource
    }()
    
    private var videoTrack: RTCVideoTrack? {
        didSet {
            if let videoTrack = videoTrack {
                // Use original video resolution to maintain quality
                // The AVSampleBufferDisplayLayer will handle scaling with resizeAspectFill
                let frameRenderer = PictureInPictureFrameRender(
                    displayLayer: pictureInPictureVideoCallViewController.videoDisplayView.sampleBufferDisplayLayer,
                    flipFrame: true
                )
                
                pictureInPictureVideoCallViewController.set(frameRenderer: frameRenderer)
                videoTrack.add(frameRenderer)
            } else {
                if let frameRenderer = pictureInPictureVideoCallViewController.frameRenderer {
                    frameRenderer.clean()
                    if let oldTrack = oldValue {
                        oldTrack.remove(frameRenderer)
                    }
                }
            }
        }
    }
                
    // MARK: - Functions
            
    override func viewDidLoad() {
        super.viewDidLoad()
                        
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        // Picture in picture needs to be called here,
        // something about being a lazy var causes it not to start
        pictureInPictureController.delegate = self
        pictureInPictureController.canStartPictureInPictureAutomaticallyFromInline = false
    }
        
    func set(track: RTCVideoTrack?) {
        self.videoTrack = track
    }
    
    func set(host: Host?) {
        guard let host = host else {
            return
        }
        
        pictureInPictureVideoCallViewController.avatarView.set(backgroundColor: host.avatarColor)
        pictureInPictureVideoCallViewController.avatarView.set(initials: host.initials)
        pictureInPictureVideoCallViewController.avatarView.isHidden = host.isCameraEnabled
        pictureInPictureVideoCallViewController.muteImageView.isHidden = host.isMicrophoneEnabled
        
        host.muteDidChange = { [weak self] publication in
            switch publication.kind {
            case .audio:
                await MainActor.run {
                    self?.pictureInPictureVideoCallViewController.muteImageView.isHidden = !publication.isMuted
                }
            case .video:
                await MainActor.run {
                    self?.pictureInPictureVideoCallViewController.avatarView.isHidden = !publication.isMuted
                    // Do this somewhere else?
                    if let videoTrack = publication.track?.mediaTrack as? RTCVideoTrack {
                        self?.videoTrack = videoTrack
                    }
                }
            default:
                break
            }
        }
    }
}

extension PictureInPictureViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        Logger.debug(
            logLevel: .error,
            scope: .core,
            message: "Failed to start picture in picture",
            error: error
        )
                
        Task {
            // Instead of polling to start it would be better to monitor the mic permission and start once that has been dismissed.
            try await Task.sleep(nanoseconds: 100_000_000)
            pictureInPictureController.startPictureInPicture()
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        guard let delegate = delegate else {
            return true
        }
    
        return await delegate.pictureInPictureController(pictureInPictureController)
    }
}

class SampleBufferVideoCallView: UIView {
    override class var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }
    
    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        let layer = self.layer as! AVSampleBufferDisplayLayer
        layer.videoGravity = .resizeAspectFill
        return layer
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupLayer()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        sampleBufferDisplayLayer.videoGravity = .resizeAspectFill
    }
}

class PictureInPictureVideoCallViewController: AVPictureInPictureVideoCallViewController {
    
    // MARK: - Properties
    
    lazy var videoDisplayView: SampleBufferVideoCallView = {
        let videoDisplayView = SampleBufferVideoCallView()
        videoDisplayView.translatesAutoresizingMaskIntoConstraints = false
        videoDisplayView.layer.cornerRadius = 16
        videoDisplayView.layer.masksToBounds = true
        return videoDisplayView
    }()
            
    var frameRenderer: PictureInPictureFrameRender?
    
    lazy var avatarView: AvatarView = {
        let avatarView = AvatarView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 16
        return avatarView
    }()
    
    lazy var muteImageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.image = UIImage(systemName: "microphone.slash")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        return imageView
    }()
    
    // MARK: - Functions
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .clear
        view.layer.cornerRadius = 16
        
        view.addSubview(videoDisplayView)
        view.addSubview(avatarView)
        view.addSubview(muteImageView)

        NSLayoutConstraint.activate([
            videoDisplayView.topAnchor.constraint(equalTo: view.topAnchor),
            videoDisplayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoDisplayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoDisplayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: view.topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            avatarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        NSLayoutConstraint.activate([
            muteImageView.widthAnchor.constraint(equalToConstant: 22),
            muteImageView.heightAnchor.constraint(equalToConstant: 22),
            muteImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            muteImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }
    
    func set(frameRenderer: PictureInPictureFrameRender) {
        self.frameRenderer?.clean()
        self.frameRenderer = frameRenderer
    }
}

class PictureInPictureFrameRender : NSObject, RTCVideoRenderer {
    
    // MARK: - Properties
    
    var displayLayer : AVSampleBufferDisplayLayer
    
    let flipFrame: Bool
    
    var shouldRenderFrame = true

    var isReady = true

    var pixelBuffer: CVPixelBuffer?
    
    var pixelBufferKey: String?
    
    private var pixelBufferPool: CVPixelBufferPool?

    private var frameProcessingQueue = DispatchQueue(label: "FrameProcessingQueue")

    private let synchronizationQueue = DispatchQueue(label: "com.userkit.synchronizationQueue")

    // MARK: - Functions
    
    init(displayLayer: AVSampleBufferDisplayLayer, flipFrame: Bool = false) {
        self.displayLayer = displayLayer
        self.flipFrame = flipFrame
    }
    
    func setSize(_ size: CGSize) {}
    
    func clean() {
        shouldRenderFrame = false
    }
    
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else {
            return
        }
        
        synchronizationQueue.async { [weak self] in
            guard let self = self else {return}
            if self.isReady {
                self.isReady = false
                self.frameProcessingQueue.async { [weak self] in
                    guard let self = self else {return}
                    if let sampleBuffer = self.handleRTCVideoFrame(frame) {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else {return}
                            if self.displayLayer.isReadyForMoreMediaData && shouldRenderFrame {
                                self.displayLayer.enqueue(sampleBuffer)
                            }
                        }
                    }
                    self.synchronizationQueue.async {
                        self.isReady = true
                    }
                }
            }
        }
    }
    
    private func frameToPixelBuffer(frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let buffer = frame.buffer as? RTCCVPixelBuffer {
            return buffer.pixelBuffer
        } else if let buffer = frame.buffer as? RTCI420Buffer {
            return createPixelBuffer(from: buffer)
        }
        
        return nil
    }
    
    private func handleRTCVideoFrame(_ frame: RTCVideoFrame) -> CMSampleBuffer? {
        if let pixelBuffer = frameToPixelBuffer(frame: frame) {
            return createSampleBufferFromPixelBuffer(pixelBuffer: pixelBuffer)
        }
        return nil
    }
        
    private func createPixelBuffer(from i420Buffer: RTCI420Buffer) -> CVPixelBuffer? {
        var width = Int(i420Buffer.width)
        var height = Int(i420Buffer.height)
        
        if width%2 != 0 {
            width += 1
        }
        if height%2 != 0 {
            height += 1
        }
        
        let tempKey = "\(width)_\(height)"
        if tempKey != pixelBufferKey {
            pixelBuffer = nil
            pixelBufferKey = tempKey
        }
        
        if pixelBuffer == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                attributes as CFDictionary,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess else {
                return nil
            }
        }
        
        
        guard let createdPixelBuffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(createdPixelBuffer, [])
        
        if let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(createdPixelBuffer, 0) {
            let yDestination = yBaseAddress.assumingMemoryBound(to: UInt8.self)
            let ySource = i420Buffer.dataY
            let yStride = CVPixelBufferGetBytesPerRowOfPlane(createdPixelBuffer, 0)
            
            for row in 0..<height {
                for col in 0..<width {
                    if flipFrame {
                        let flippedCol = Int(i420Buffer.width) - 1 - col
                        yDestination[row * yStride + col] = ySource[row * Int(i420Buffer.strideY) + flippedCol]
                    } else {
                        yDestination[row * yStride + col] = ySource[row * Int(i420Buffer.strideY) + col]
                    }
                }
            }
        }
        
        if let uvBaseAddress = CVPixelBufferGetBaseAddressOfPlane(createdPixelBuffer, 1) {
            let uvDestination = uvBaseAddress.assumingMemoryBound(to: UInt8.self)
            let uSource = i420Buffer.dataU
            let vSource = i420Buffer.dataV
            let uvStride = CVPixelBufferGetBytesPerRowOfPlane(createdPixelBuffer, 1)
            
            for row in 0..<height / 2 {
                for col in 0..<width / 2 {
                    let uvIndex = row * uvStride + col * 2
                    if flipFrame {
                        let flippedCol = Int(i420Buffer.width/2) - 1 - col
                        uvDestination[uvIndex] = uSource[row * Int(i420Buffer.strideU) + flippedCol]
                        uvDestination[uvIndex + 1] = vSource[row * Int(i420Buffer.strideV) + flippedCol]
                    }else {
                        uvDestination[uvIndex] = uSource[row * Int(i420Buffer.strideU) + col]
                        uvDestination[uvIndex + 1] = vSource[row * Int(i420Buffer.strideV) + col]
                    }
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(createdPixelBuffer, [])
        
        return createdPixelBuffer
    }
    
    private func createSampleBufferFromPixelBuffer(pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDescription)
        
        guard let formatDescription = formatDescription else {
            return nil
        }
        
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo()
        timingInfo.duration = CMTime.invalid
        timingInfo.decodeTimeStamp = CMTime.invalid
        timingInfo.presentationTimeStamp = CMTime(value: CMTimeValue(CACurrentMediaTime() * 1000), timescale: 1000)
        
        let status = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                        imageBuffer: pixelBuffer,
                                                        dataReady: true,
                                                        makeDataReadyCallback: nil,
                                                        refcon: nil,
                                                        formatDescription: formatDescription,
                                                        sampleTiming: &timingInfo,
                                                        sampleBufferOut: &sampleBuffer)
        if status != noErr {
            return nil
        }
        
        return sampleBuffer
    }
}

class AvatarView: UIView {
    
    // MARK: - Properties
    
    private lazy var initialsLabel: UILabel = {
        let label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = ""
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 32, weight: .medium)
        label.textAlignment = .center
        return label
    }()
    
    // MARK: - Functions
        
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .clear
        
        addSubview(initialsLabel)
        
        NSLayoutConstraint.activate([
            initialsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
            
    func set(initials: String) {
        initialsLabel.text = initials
    }
    
    func set(backgroundColor: UIColor) {
        self.backgroundColor = backgroundColor
    }
}

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

    private var localVideoTrack: RTCVideoTrack? {
        didSet {
            if let localVideoTrack = localVideoTrack {
                let localFrameRenderer = PictureInPictureFrameRender(
                    displayLayer: pictureInPictureVideoCallViewController.localVideoDisplayView.sampleBufferDisplayLayer,
                    flipFrame: true
                )

                pictureInPictureVideoCallViewController.set(localFrameRenderer: localFrameRenderer)
                localVideoTrack.add(localFrameRenderer)
            } else {
                if let localFrameRenderer = pictureInPictureVideoCallViewController.localFrameRenderer {
                    localFrameRenderer.clean()
                    if let oldTrack = oldValue {
                        oldTrack.remove(localFrameRenderer)
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

    func set(localTrack: RTCVideoTrack?) {
        self.localVideoTrack = localTrack
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

    func set(user: User?) {
        guard let user = user else {
            return
        }

        pictureInPictureVideoCallViewController.localAvatarView.set(backgroundColor: UIColor(red: 0.89, green: 0.47, blue: 0.33, alpha: 1.0))
        pictureInPictureVideoCallViewController.localAvatarView.set(initials: "You")
        pictureInPictureVideoCallViewController.localAvatarView.isHidden = user.isCameraEnabled
        pictureInPictureVideoCallViewController.localMuteImageView.isHidden = user.isMicrophoneEnabled

        user.muteDidChange = { [weak self] publication in
            switch publication.source {
            case .microphone:
                await MainActor.run {
                    self?.pictureInPictureVideoCallViewController.localMuteImageView.isHidden = !publication.isMuted
                }
            case .camera:
                await MainActor.run {
                    self?.pictureInPictureVideoCallViewController.localAvatarView.isHidden = !publication.isMuted
                    // Do this somewhere else?
                    if let videoTrack = publication.track?.mediaTrack as? RTCVideoTrack {
                        self?.localVideoTrack = videoTrack
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
        return videoDisplayView
    }()

    var frameRenderer: PictureInPictureFrameRender?

    var localFrameRenderer: PictureInPictureFrameRender?

    lazy var avatarView: AvatarView = {
        let avatarView = AvatarView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        return avatarView
    }()

    lazy var muteImageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.image = UIImage(systemName: "microphone.slash")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        return imageView
    }()

    lazy var localVideoDisplayView: SampleBufferVideoCallView = {
        let localVideoDisplayView = SampleBufferVideoCallView()
        localVideoDisplayView.translatesAutoresizingMaskIntoConstraints = false
        localVideoDisplayView.backgroundColor = .black
        return localVideoDisplayView
    }()

    lazy var localAvatarView: AvatarView = {
        let localAvatarView = AvatarView()
        localAvatarView.translatesAutoresizingMaskIntoConstraints = false
        return localAvatarView
    }()
    
    lazy var localMuteImageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.image = UIImage(systemName: "microphone.slash")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        return imageView
    }()

    // MARK: - Functions

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        preferredContentSize = CGSize(width: 1080, height: 1920)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        preferredContentSize = CGSize(width: 1080, height: 1920)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        view.addSubview(videoDisplayView)
        view.addSubview(avatarView)
        view.addSubview(muteImageView)
        view.addSubview(localVideoDisplayView)
        view.addSubview(localAvatarView)
        view.addSubview(localMuteImageView)

        NSLayoutConstraint.activate([
            videoDisplayView.topAnchor.constraint(equalTo: view.topAnchor),
            videoDisplayView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),
            videoDisplayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoDisplayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: view.topAnchor),
            avatarView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),
            avatarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            muteImageView.widthAnchor.constraint(equalToConstant: 22),
            muteImageView.heightAnchor.constraint(equalToConstant: 22),
            muteImageView.leadingAnchor.constraint(equalTo: videoDisplayView.leadingAnchor, constant: 8),
            muteImageView.bottomAnchor.constraint(equalTo: videoDisplayView.bottomAnchor, constant: -8)
        ])

        NSLayoutConstraint.activate([
            localVideoDisplayView.topAnchor.constraint(equalTo: videoDisplayView.bottomAnchor),
            localVideoDisplayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            localVideoDisplayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            localVideoDisplayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            localAvatarView.topAnchor.constraint(equalTo: videoDisplayView.bottomAnchor),
            localAvatarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            localAvatarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            localAvatarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        NSLayoutConstraint.activate([
            localMuteImageView.widthAnchor.constraint(equalToConstant: 22),
            localMuteImageView.heightAnchor.constraint(equalToConstant: 22),
            localMuteImageView.leadingAnchor.constraint(equalTo: localVideoDisplayView.leadingAnchor, constant: 8),
            localMuteImageView.bottomAnchor.constraint(equalTo: localVideoDisplayView.bottomAnchor, constant: -8)
        ])
    }
    
    func set(frameRenderer: PictureInPictureFrameRender) {
        self.frameRenderer?.clean()
        self.frameRenderer = frameRenderer
    }

    func set(localFrameRenderer: PictureInPictureFrameRender) {
        self.localFrameRenderer?.clean()
        self.localFrameRenderer = localFrameRenderer
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

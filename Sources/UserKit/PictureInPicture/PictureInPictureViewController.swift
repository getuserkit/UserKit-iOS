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
import Accelerate

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
            pictureInPictureVideoCallViewController.hostView.setVideoTrack(videoTrack, oldTrack: oldValue)
        }
    }

    private var localVideoTrack: RTCVideoTrack? {
        didSet {
            pictureInPictureVideoCallViewController.userView.setVideoTrack(localVideoTrack, oldTrack: oldValue)
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

        pictureInPictureVideoCallViewController.hostView.configure(participant: host)

        host.muteDidChange = { [weak self] publication in
            switch publication.source {
            case .microphone:
                await MainActor.run {
                    self?.pictureInPictureVideoCallViewController.hostView.updateMuteState(isMuted: publication.isMuted)
                }
            case .camera:
                await MainActor.run {
                    self?.pictureInPictureVideoCallViewController.hostView.avatarView.isHidden = !publication.isMuted
                    if let videoTrack = publication.track?.mediaTrack as? RTCVideoTrack {
                        self?.videoTrack = videoTrack
                    }
                }
            default:
                break
            }
        }

        host.audioLevelDidChange = { [weak self] level in
            await MainActor.run {
                self?.pictureInPictureVideoCallViewController.hostView.updateAudioLevel(level)
            }
        }
    }

    func set(user: User?) {
        guard let user = user else {
            return
        }

        pictureInPictureVideoCallViewController.userView.configure(participant: user)

        user.muteDidChange = { [weak self] publication in
            switch publication.source {
            case .microphone:
                await MainActor.run {
                    self?.pictureInPictureVideoCallViewController.userView.updateMuteState(isMuted: publication.isMuted)
                }
            case .camera:
                await MainActor.run {
                    self?.pictureInPictureVideoCallViewController.userView.avatarView.isHidden = !publication.isMuted
                    if let videoTrack = publication.track?.mediaTrack as? RTCVideoTrack {
                        self?.localVideoTrack = videoTrack
                    }
                }
            default:
                break
            }
        }

        user.audioLevelDidChange = { [weak self] level in
            await MainActor.run {
                self?.pictureInPictureVideoCallViewController.userView.updateAudioLevel(level)
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

    lazy var hostView: ParticipantView = {
        let view = ParticipantView()
        return view
    }()

    lazy var userView: ParticipantView = {
        let view = ParticipantView()
        view.videoDisplayView.backgroundColor = .black
        return view
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

        let midAnchor = view.centerYAnchor
        hostView.setupConstraints(in: view, topAnchor: view.topAnchor, bottomAnchor: midAnchor)
        userView.setupConstraints(in: view, topAnchor: midAnchor, bottomAnchor: view.bottomAnchor)
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
            let sourceYStride = Int(i420Buffer.strideY)

            var srcBuffer = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: ySource),
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: sourceYStride
            )

            var destBuffer = vImage_Buffer(
                data: yDestination,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: yStride
            )

            if flipFrame {
                vImageHorizontalReflect_Planar8(&srcBuffer, &destBuffer, vImage_Flags(kvImageNoFlags))
            } else {
                vImageCopyBuffer(&srcBuffer, &destBuffer, 1, vImage_Flags(kvImageNoFlags))
            }
        }

        if let uvBaseAddress = CVPixelBufferGetBaseAddressOfPlane(createdPixelBuffer, 1) {
            let uvDestination = uvBaseAddress.assumingMemoryBound(to: UInt8.self)
            let uSource = i420Buffer.dataU
            let vSource = i420Buffer.dataV
            let uvStride = CVPixelBufferGetBytesPerRowOfPlane(createdPixelBuffer, 1)
            let chromaWidth = width / 2
            let chromaHeight = height / 2
            let sourceUVStride = Int(i420Buffer.strideU)

            if flipFrame {
                for row in 0..<chromaHeight {
                    for col in 0..<chromaWidth {
                        let flippedCol = chromaWidth - 1 - col
                        let uvIndex = row * uvStride + col * 2
                        uvDestination[uvIndex] = uSource[row * sourceUVStride + flippedCol]
                        uvDestination[uvIndex + 1] = vSource[row * sourceUVStride + flippedCol]
                    }
                }
            } else {
                for row in 0..<chromaHeight {
                    let srcURow = uSource.advanced(by: row * sourceUVStride)
                    let srcVRow = vSource.advanced(by: row * sourceUVStride)
                    let dstUVRow = uvDestination.advanced(by: row * uvStride)

                    for col in 0..<chromaWidth {
                        dstUVRow[col * 2] = srcURow[col]
                        dstUVRow[col * 2 + 1] = srcVRow[col]
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

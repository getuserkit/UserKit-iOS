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
    
    private var videoTracks: [String: RTCVideoTrack] = [:]

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
        
    func set(hosts: [Host], user: User?) {
        pictureInPictureVideoCallViewController.updateParticipants(hosts: hosts, user: user)

        for host in hosts {
            host.muteDidChange = { [weak self] publication in
                switch publication.source {
                case .microphone:
                    await MainActor.run {
                        self?.pictureInPictureVideoCallViewController.getParticipantView(for: host.id)?.updateMuteState(isMuted: publication.isMuted)
                    }
                case .camera:
                    await MainActor.run {
                        self?.pictureInPictureVideoCallViewController.getParticipantView(for: host.id)?.updateCameraState(isEnabled: !publication.isMuted)
                        if let videoTrack = publication.track?.mediaTrack as? RTCVideoTrack {
                            self?.setVideoTrack(videoTrack, for: host.id)
                        } else {
                            self?.removeVideoTrack(for: host.id)
                        }
                    }
                default:
                    break
                }
            }
        }

        if let user = user {
            user.muteDidChange = { [weak self] publication in
                switch publication.source {
                case .microphone:
                    await MainActor.run {
                        self?.pictureInPictureVideoCallViewController.getParticipantView(for: user.id)?.updateMuteState(isMuted: publication.isMuted)
                    }
                case .camera:
                    await MainActor.run {
                        self?.pictureInPictureVideoCallViewController.getParticipantView(for: user.id)?.updateCameraState(isEnabled: !publication.isMuted)
                        if let videoTrack = publication.track?.mediaTrack as? RTCVideoTrack {
                            self?.setVideoTrack(videoTrack, for: user.id)
                        } else {
                            self?.removeVideoTrack(for: user.id)
                        }
                    }
                default:
                    break
                }
            }
        }
    }

    private func setVideoTrack(_ track: RTCVideoTrack, for participantId: String) {
        let oldTrack = videoTracks[participantId]
        videoTracks[participantId] = track

        if let participantView = pictureInPictureVideoCallViewController.getParticipantView(for: participantId) {
            participantView.setVideoTrack(track, oldTrack: oldTrack)
        }
    }

    private func removeVideoTrack(for participantId: String) {
        let oldTrack = videoTracks.removeValue(forKey: participantId)

        if let participantView = pictureInPictureVideoCallViewController.getParticipantView(for: participantId) {
            participantView.setVideoTrack(nil, oldTrack: oldTrack)
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

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private var participantViews: [String: ParticipantView] = [:]

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

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func updateParticipants(hosts: [Host], user: User?) {
        var participants: [Participant] = hosts
        if let user = user {
            participants.append(user)
        }

        let newParticipantIds = Set(participants.map { $0.id })
        let existingParticipantIds = Set(participantViews.keys)

        let participantsToRemove = existingParticipantIds.subtracting(newParticipantIds)
        for participantId in participantsToRemove {
            if let participantView = participantViews[participantId] {
                UIView.animate(withDuration: 0.3, animations: {
                    participantView.alpha = 0
                }) { _ in
                    participantView.clean()
                    participantView.removeFromSuperview()
                }
                participantViews.removeValue(forKey: participantId)
            }
        }

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for participant in participants {
            let participantView: ParticipantView
            if let existingView = participantViews[participant.id] {
                participantView = existingView
            } else {
                participantView = ParticipantView()
                participantView.configure(participant: participant, isLocalUser: participant is User)
                participantView.alpha = 0
                participantViews[participant.id] = participantView
            }

            stackView.addArrangedSubview(participantView)

            if participantView.alpha == 0 {
                UIView.animate(withDuration: 0.3) {
                    participantView.alpha = 1
                }
            }
        }
    }

    func getParticipantView(for participantId: String) -> ParticipantView? {
        return participantViews[participantId]
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

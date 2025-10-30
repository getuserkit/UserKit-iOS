//
//  CameraCapturer.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import WebRTC

class CameraCapturer: VideoCapturer, @unchecked Sendable {
    
    // MARK: - Types
    
    struct State {
        var device: AVCaptureDevice?
        var options: CameraCaptureOptions
    }
    
    // MARK: - Properties
    
    static func captureDevices() async throws -> [AVCaptureDevice] {
        try await DeviceManager.shared.devices()
    }
    
    var device: AVCaptureDevice? { cameraCapturerState.device }

    var options: CameraCaptureOptions { cameraCapturerState.options }
    
    private weak var delegate: RTCVideoCapturerDelegate?
    
    private lazy var adapter: VideoCapturerDelegateAdapter = .init(cameraCapturer: self)
    
    private lazy var capturer: RTCCameraVideoCapturer = .init(delegate: adapter)
    
    private var cameraCapturerState: StateSync<State>
        
    // MARK: - Functions
    
    override init(delegate: RTCVideoCapturerDelegate) {
        self.delegate = delegate
        self.cameraCapturerState = StateSync(State(options: .init()))

        super.init(delegate: delegate)
    }
    
    override public func startCapture() async throws -> Bool {
        let didStart = try await super.startCapture()

        // Already started
        guard didStart else { return false }

        var devices: [AVCaptureDevice]
        if AVCaptureMultiCamSession.isMultiCamSupported {
            // Get the list of devices already on the shared multi-cam session.
            let existingDevices = capturer.captureSession.inputs.compactMap { $0 as? AVCaptureDeviceInput }.map(\.device)
            // Compute other multi-cam compatible devices.
            devices = try await DeviceManager.shared.multiCamCompatibleDevices(for: Set(existingDevices))
        } else {
            devices = try await CameraCapturer.captureDevices()
        }

        let device = devices.first { $0.position == .front } ?? devices.first

        guard let device else {
            throw UserKitError.deviceNotFound
        }

        // list of all formats in order of dimensions size
        let formats = DispatchQueue.userKitWebRTC.sync { RTCCameraVideoCapturer.supportedFormats(for: device) }
        // create an array of sorted touples by dimensions size
        let sortedFormats = formats.map { (format: $0, dimensions: Dimensions(from: CMVideoFormatDescriptionGetDimensions($0.formatDescription))) }
            .sorted { $0.dimensions.area < $1.dimensions.area }

        // default to the largest supported dimensions (backup)
        var selectedFormat = sortedFormats.last
        
        if let foundFormat = sortedFormats.first(where: { ($0.dimensions.width >= self.options.dimensions.width && $0.dimensions.height >= self.options.dimensions.height) && $0.format.fpsRange().contains(self.options.fps) && $0.format.filterForMulticamSupport }) {
            // Use the first format that satisfies preferred dimensions & fps
            selectedFormat = foundFormat
        } else if let foundFormat = sortedFormats.first(where: { $0.dimensions.width >= self.options.dimensions.width && $0.dimensions.height >= self.options.dimensions.height }) {
            // Use the first format that satisfies preferred dimensions (without fps)
            selectedFormat = foundFormat
        }

        // format should be resolved at this point
        guard let selectedFormat else {
            throw UserKitError.captureFormatNotFound
        }

        let fpsRange = selectedFormat.format.fpsRange()

        // this should never happen
        guard fpsRange != 0 ... 0 else {
            throw UserKitError.unableToResolveFPSRange
        }

        // default to fps in options
        var selectedFps = cameraCapturerState.options.fps

        if !fpsRange.contains(selectedFps) {
            selectedFps = selectedFps.clamped(to: fpsRange)
        }
        
        try await capturer.startCapture(with: device, format: selectedFormat.format, fps: selectedFps)

        cameraCapturerState.mutate { $0.device = device }

        return true
    }

    override public func stopCapture() async throws -> Bool {
        let didStop = try await super.stopCapture()

        // Already stopped
        guard didStop else { return false }

        await capturer.stopCapture()

        return true
    }
}

extension LocalVideoTrack {
    static func createCameraTrack(name: String? = nil, isMuted: Bool) -> LocalVideoTrack {
        let videoSource = RTC.createVideoSource(forScreenShare: false)
        let capturer = CameraCapturer(delegate: videoSource)
        return LocalVideoTrack(name: name ?? Track.cameraName, source: .camera, capturer: capturer, videoSource: videoSource, isMuted: isMuted)
    }
}

class VideoCapturerDelegateAdapter: NSObject, RTCVideoCapturerDelegate {
    
    // MARK: - Properties
    
    weak var cameraCapturer: CameraCapturer?

    // MARK: - Functions
    
    init(cameraCapturer: CameraCapturer? = nil) {
        self.cameraCapturer = cameraCapturer
    }

    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        guard let cameraCapturer else { return }

        // Pass frame to video source without cropping
        cameraCapturer.capture(frame: frame, capturer: capturer, device: cameraCapturer.device, options: cameraCapturer.options)
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension AVCaptureDevice.Format {
    // computes a ClosedRange of supported FPSs for this format
    func fpsRange() -> ClosedRange<Int> {
        videoSupportedFrameRateRanges.map { $0.toRange() }.reduce(into: 0 ... 0) { result, current in
            result = merge(range: result, with: current)
        }
    }

    // Used for filtering.
    // Only include multi-cam supported devices if in multi-cam mode. Otherwise, always include the devices.
    var filterForMulticamSupport: Bool {
        return AVCaptureMultiCamSession.isMultiCamSupported ? isMultiCamSupported : true
    }
}

extension AVFrameRateRange {
    // convert to a ClosedRange
    func toRange() -> ClosedRange<Int> {
        Int(minFrameRate) ... Int(maxFrameRate)
    }
}

extension RTCVideoFrame {
    func cropAndScaleFromCenter(
        targetWidth: Int32,
        targetHeight: Int32
    ) -> RTCVideoFrame? {
        // Ensure target dimensions don't exceed source dimensions
        let scaleWidth: Int32
        let scaleHeight: Int32

        if targetWidth > width || targetHeight > height {
            // Calculate scale factor to fit within source dimensions
            let widthScale = Double(targetWidth) / Double(width) // Scale down factor
            let heightScale = Double(targetHeight) / Double(height)
            let scale = max(widthScale, heightScale)

            // Apply scale to target dimensions
            scaleWidth = Int32(Double(targetWidth) / scale)
            scaleHeight = Int32(Double(targetHeight) / scale)
        } else {
            scaleWidth = targetWidth
            scaleHeight = targetHeight
        }

        // Calculate aspect ratios
        let sourceRatio = Double(width) / Double(height)
        let targetRatio = Double(scaleWidth) / Double(scaleHeight)

        // Calculate crop dimensions
        let (cropWidth, cropHeight): (Int32, Int32)
        if sourceRatio > targetRatio {
            // Source is wider - crop width
            cropHeight = height
            cropWidth = Int32(Double(height) * targetRatio)
        } else {
            // Source is taller - crop height
            cropWidth = width
            cropHeight = Int32(Double(width) / targetRatio)
        }

        // Calculate center offsets
        let offsetX = (width - cropWidth) / 2
        let offsetY = (height - cropHeight) / 2

        guard let newBuffer = buffer.cropAndScale?(
            with: offsetX,
            offsetY: offsetY,
            cropWidth: cropWidth,
            cropHeight: cropHeight,
            scaleWidth: scaleWidth,
            scaleHeight: scaleHeight
        ) else { return nil }

        return RTCVideoFrame(buffer: newBuffer, rotation: rotation, timeStampNs: timeStampNs)
    }
}

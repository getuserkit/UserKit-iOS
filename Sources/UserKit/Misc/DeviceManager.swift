/*
 * Copyright 2025 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

@preconcurrency import AVFoundation

class DeviceManager: @unchecked Sendable {
    
    // MARK: - Properties

    static let shared = DeviceManager()

    static func prepare() {
        _ = shared
    }
    
    static func ensureDeviceAccess(for types: Set<AVMediaType>) async -> Bool {
        for type in types {
            if ![.video, .audio].contains(type) {
                Logger.debug(logLevel: .error, scope: .core, message: "types must be .video or .audio")
            }

            let status = AVCaptureDevice.authorizationStatus(for: type)
            switch status {
            case .notDetermined:
                if await !(AVCaptureDevice.requestAccess(for: type)) {
                    return false
                }
            case .restricted, .denied: return false
            case .authorized: continue // No action needed for authorized status.
            @unknown default:
                Logger.debug(logLevel: .error, scope: .core, message: "Unknown AVAuthorizationStatus")
                return false
            }
        }

        return true
    }

    func devices() async throws -> [AVCaptureDevice] {
        try await devicesCompleter.wait()
    }

    func devices() -> [AVCaptureDevice] {
        state.devices
    }

    private lazy var discoverySession: AVCaptureDevice.DiscoverySession = {
        var deviceTypes: [AVCaptureDevice.DeviceType]
        // In order of priority
        deviceTypes = [
            .builtInTripleCamera, // Virtual, switchOver: [2, 6], default: 2
            .builtInDualCamera, // Virtual, switchOver: [3], default: 1
            .builtInDualWideCamera, // Virtual, switchOver: [2], default: 2
            .builtInWideAngleCamera, // Physical, General purpose use
            .builtInTelephotoCamera, // Physical
            .builtInUltraWideCamera, // Physical
        ]

        // Xcode 15.0 Swift 5.9
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            deviceTypes.append(contentsOf: [
                .continuityCamera,
                .external,
            ])
        }

        return AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                mediaType: .video,
                                                position: .unspecified)
    }()

    private struct State {
        var devices: [AVCaptureDevice] = []
        var multiCamDeviceSets: [Set<AVCaptureDevice>] = []
    }

    private let state = StateSync(State())

    private let devicesCompleter = AsyncCompleter<[AVCaptureDevice]>(label: "devices", defaultTimeout: 10)
    private let multiCamDeviceSetsCompleter = AsyncCompleter<[Set<AVCaptureDevice>]>(label: "multiCamDeviceSets", defaultTimeout: 10)

    private var devicesObservation: NSKeyValueObservation?
    private var multiCamDeviceSetsObservation: NSKeyValueObservation?

    /// Find multi-cam compatible devices.
    func multiCamCompatibleDevices(for devices: Set<AVCaptureDevice>) async throws -> [AVCaptureDevice] {
        let deviceSets = try await multiCamDeviceSetsCompleter.wait()

        let compatibleDevices = deviceSets.filter { $0.isSuperset(of: devices) }
            .reduce(into: Set<AVCaptureDevice>()) { $0.formUnion($1) }
            .subtracting(devices)

        let devices = try await devicesCompleter.wait()

        // This ensures the ordering is same as the devices array.
        return devices.filter { compatibleDevices.contains($0) }
    }

    init() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            devicesObservation = discoverySession.observe(\.devices, options: [.initial, .new]) { [weak self] _, value in
                guard let self else { return }
                let devices = (value.newValue ?? []).sortedByFacingPositionPriority()
                state.mutate { $0.devices = devices }
                devicesCompleter.resume(returning: devices)
            }
        }

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            multiCamDeviceSetsObservation = discoverySession.observe(\.supportedMultiCamDeviceSets, options: [.initial, .new]) { [weak self] _, value in
                guard let self else { return }
                let deviceSets = (value.newValue ?? [])
                state.mutate { $0.multiCamDeviceSets = deviceSets }
                multiCamDeviceSetsCompleter.resume(returning: deviceSets)
            }
        }
    }
}

extension [AVCaptureDevice] {
    /// Sort priority: .front = 2, .back = 1, .unspecified = 3.
    func sortedByFacingPositionPriority() -> [Element] {
        sorted(by: { $0.facingPosition.rawValue > $1.facingPosition.rawValue })
    }
}

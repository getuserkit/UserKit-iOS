//
//  Transport.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation
import WebRTC

actor Transport: NSObject {
    
    // MARK: - Types
    
    typealias OnConnectionStateChangeBlock = @Sendable (RTCPeerConnectionState) async -> Void
    
    typealias OnDidAddBlock = @Sendable (RTCPeerConnection, RTCRtpReceiver, [RTCMediaStream]) async -> Void
    
    typealias OnOfferBlock = @Sendable (RTCSessionDescription) async throws -> Void
    
    // MARK: - Properties
    
    var onConnectionStateChange: OnConnectionStateChangeBlock?
    
    var onDidAdd: OnDidAddBlock?
    
    var onOffer: OnOfferBlock?
    
    var transceivers: [RTCRtpTransceiver] {
        peerConnection.transceivers
    }
    
    private var renegotiate: Bool = false
    
    private let peerConnection: RTCPeerConnection
        
    private let debounce = Debounce(delay: 0.02)
    
    // MARK: - Functions
    
    init(configuration: RTCConfiguration) throws {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()

        let factory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )

        guard let peerConnection = factory.peerConnection(with: configuration, constraints: constraints, delegate: nil) else {
            throw UserKitError.invalidState
        }

        self.peerConnection = peerConnection
        
        super.init()
        
        self.peerConnection.delegate = self
    }

    func set(onConnectionStateChange block: @escaping OnConnectionStateChangeBlock) {
        self.onConnectionStateChange = block
    }
    
    func set(onOfferBlock block: @escaping OnOfferBlock) {
        self.onOffer = block
    }
    
    func set(onDidAdd block: @escaping OnDidAddBlock) {
        self.onDidAdd = block
    }
    
    func set(localDescription sessionDescription: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(sessionDescription) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func set(remoteDescription sessionDescription: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(sessionDescription) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        if renegotiate {
            renegotiate = false
            try await createAndSendOffer()
        }
    }
    
    @discardableResult
    func addTransceiver(with track: RTCMediaStreamTrack, transceiverInit: RTCRtpTransceiverInit) throws -> RTCRtpTransceiver {
        guard let transceiver = peerConnection.addTransceiver(with: track, init: transceiverInit) else {
            throw UserKitError.invalidState
        }

        return transceiver
    }
    
    func addTransceiver(of type: RTCRtpMediaType, transceiverInit: RTCRtpTransceiverInit) throws -> RTCRtpTransceiver {
        guard let transceiver = peerConnection.addTransceiver(of: type, init: transceiverInit) else {
            throw UserKitError.invalidState
        }
        
        return transceiver
    }
    
    func remove(track sender: RTCRtpSender) throws {
        guard peerConnection.removeTrack(sender) else {
            throw UserKitError.webRTC
        }
    }
    
    func createAndSendOffer() async throws {
        guard let onOffer else {
            Logger.debug(logLevel: .error, scope: .core, message: "onOffer is nil")
            return
        }

        if peerConnection.signalingState == .haveLocalOffer, !(peerConnection.remoteDescription != nil) {
            self.renegotiate = true
            return
        }

        func negotiate() async throws {
            let constraints = [String: String]()
            let offer = try await createOffer(for: constraints)
            try await set(localDescription: offer)
            try await onOffer(offer)
        }

        if peerConnection.signalingState == .haveLocalOffer, let sessionDescription = peerConnection.remoteDescription {
            try await set(remoteDescription: sessionDescription)
            return try await negotiate()
        }

        try await negotiate()
    }
    
    func createAnswer() async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            
            peerConnection.answer(for: constraints) { sessionDescription, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sessionDescription = sessionDescription else {
                    continuation.resume(throwing: UserKitError.invalidState)
                    return
                }
                
                continuation.resume(returning: sessionDescription)
            }
        }
    }

    func negotiate() async {
        await debounce.schedule {
            try await self.createAndSendOffer()
        }
    }
    
    func close() async {
        await debounce.cancel()

        peerConnection.delegate = nil
        for sender in peerConnection.senders {
            peerConnection.removeTrack(sender)
        }

        peerConnection.close()
    }
    
    private func createOffer(for constraints: [String: String]? = nil) async throws -> RTCSessionDescription {
        let mediaConstraints = RTCMediaConstraints(mandatoryConstraints: constraints, optionalConstraints: nil)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peerConnection.offer(for: mediaConstraints) { sessionDescription, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let sessionDescription {
                    continuation.resume(returning: sessionDescription)
                } else {
                    continuation.resume(throwing: UserKitError.invalidState)
                }
            }
        }
    }
}

extension Transport {
    func statistics(for sender: RTCRtpSender) async -> RTCStatisticsReport {
        await withCheckedContinuation { (continuation: CheckedContinuation<RTCStatisticsReport, Never>) in
            peerConnection.statistics(for: sender) { sessionDescription in
                continuation.resume(returning: sessionDescription)
            }
        }
    }

    func statistics(for receiver: RTCRtpReceiver) async -> RTCStatisticsReport {
        await withCheckedContinuation { (continuation: CheckedContinuation<RTCStatisticsReport, Never>) in
            peerConnection.statistics(for: receiver) { sd in
                continuation.resume(returning: sd)
            }
        }
    }
}

extension Transport: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        Task { await onConnectionStateChange?(state) }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnectionShouldNegotiate(_: RTCPeerConnection) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        Task { await onDidAdd?(peerConnection, rtpReceiver, streams) }
    }
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCIceConnectionState) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCSignalingState) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didAdd _: RTCMediaStream) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCIceGatheringState) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}
}

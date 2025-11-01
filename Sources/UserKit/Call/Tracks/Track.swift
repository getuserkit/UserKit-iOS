//
//  Track.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import WebRTC

class Track: NSObject, @unchecked Sendable {
    
    // MARK: - Types
    
    enum TrackState: Int, Codable, Sendable {
        case stopped
        case started
    }
    
    public enum Kind: Int, Codable, Sendable {
        case audio
        case video
        case none
        
        init(type: WebSocketClient.Message.Server.Call.Participant.Track.TrackType) {
            switch type {
            case .audio:
                self = .audio
            case .screenShare:
                self = .video
            case .video:
                self = .video
            case .unknown:
                self = .none
            }
        }
    }
    
    enum Source: Int, Codable, Sendable {
        case unknown
        case camera
        case microphone
        case screenShareVideo
        case screenShareAudio
        
        var type: String {
            switch self {
            case .camera:
                "video"
            case .microphone:
                "audio"
            case .screenShareVideo:
                "screenShare"
            default:
                "unknown"
            }
        }
        
        init(type: WebSocketClient.Message.Server.Call.Participant.Track.TrackType) {
            switch type {
            case .audio:
                self = .microphone
            case .screenShare:
                self = .screenShareVideo
            case .video:
                self = .camera
            case .unknown:
                self = .unknown
            }
        }
    }
    
    struct State {
        var isMuted: Bool
        let kind: Kind
        let name: String
        let source: Source
        var transport: Transport?
        var trackState: TrackState = .stopped
        var rtpSender: RTCRtpSender?
        var transceiver: RTCRtpTransceiver?
    }
    
    typealias MuteDidChange = @Sendable () async throws -> Void

    typealias AudioLevelDidChange = @Sendable (Float) async -> Void

    // MARK: - Properties

    static let cameraName = "camera"

    static let microphoneName = "microphone"

    static let screenShareVideoName = "screen_share"

    var muteDidChange: MuteDidChange?

    var audioLevelDidChange: AudioLevelDidChange?
        
    let mediaTrack: RTCMediaStreamTrack
    
    var isMuted: Bool { state.isMuted }
    
    var name: String { state.name }
    
    var kind: Kind { state.kind }
    
    var source: Source { state.source }

    var transceiver: RTCRtpTransceiver? { state.transceiver }
    
    let state: StateSync<State>
    
    var willStart: (() async throws -> Void)?
    
    var didStart: (() async throws -> Void)?
    
    var didStop: (() async throws -> Void)?

    private let startStopSerialRunner = SerialRunnerActor<Void>()

    private let statisticsTimer = AsyncTimer(interval: 0.1)

    // MARK: - Functions
    
    init(name: String, kind: Kind, source: Source, track: RTCMediaStreamTrack, isMuted: Bool) {
        self.mediaTrack = track
        self.state = .init(.init(isMuted: isMuted, kind: kind, name: name, source: source))

        super.init()

        statisticsTimer.setTimerBlock { [weak self] in
            await self?.reportStatistics()
        }

        statisticsTimer.restart()
    }
        
    func mute() async throws {
        guard self is LocalTrack, !isMuted else { return }
        try await disable()
        if self is LocalVideoTrack {
            try await stop()
        }
        set(muted: true)
    }
    
    func unmute() async throws {
        guard self is LocalTrack, isMuted else { return }
        if self is LocalVideoTrack {
            try await start()
        }
        try await enable()
        set(muted: false)
    }
    
    func startCapture() async throws {}
    func stopCapture() async throws {}
    
    final func start() async throws {
        try await startStopSerialRunner.run { [weak self] in
            guard let self else { return }
            guard state.trackState != .started else {
                return
            }
            try await willStart?()
            try await startCapture()
            state.mutate { $0.trackState = .started }
            try await didStart?()
        }
    }
    
    final func stop() async throws {
        try await startStopSerialRunner.run { [weak self] in
            guard let self else { return }
            guard state.trackState != .stopped else {
                return
            }
            try await stopCapture()
            if self is RemoteTrack { try await disable() }
            state.mutate { $0.trackState = .stopped }
            try await didStop?()
        }
    }
    
    @discardableResult
    func enable() async throws -> Bool {
        guard !mediaTrack.isEnabled else { return false }
        mediaTrack.isEnabled = true
        return true
    }
    
    @discardableResult
    func disable() async throws -> Bool {
        guard mediaTrack.isEnabled else { return false }
        mediaTrack.isEnabled = false
        return true
    }
    
    func set(rtpSender: RTCRtpSender, transceiver: RTCRtpTransceiver, transport: Transport?) {
        state.mutate {
            $0.rtpSender = rtpSender
            $0.transceiver = transceiver
            $0.transport = transport
        }
    }
    
    func set(muted newValue: Bool) {
        guard state.isMuted != newValue else { return }
        
        state.mutate { $0.isMuted = newValue }

        Task { try await muteDidChange?() }
    }
}

extension Track {
    func reportStatistics() async {
        guard kind == .audio else { return }

        let (transport, transceiver) = state.read { ($0.transport, $0.transceiver) }

        guard let transport, let transceiver else { return }

        let statisticsReport: RTCStatisticsReport
        if self is RemoteTrack {
            statisticsReport = await transport.statistics(for: transceiver.receiver)
        } else {
            statisticsReport = await transport.statistics(for: transceiver.sender)
        }

        if let audioLevel = extractAudioLevel(from: statisticsReport) {
            await audioLevelDidChange?(audioLevel)
        }
    }

    private func extractAudioLevel(from report: RTCStatisticsReport) -> Float? {
        for (_, stats) in report.statistics {
            if let audioLevel = stats.values["audioLevel"] as? NSNumber {
                return audioLevel.floatValue
            }

            if let audioInputLevel = stats.values["audioInputLevel"] as? NSNumber {
                return audioInputLevel.floatValue
            }

            if let audioOutputLevel = stats.values["audioOutputLevel"] as? NSNumber {
                return audioOutputLevel.floatValue
            }
        }
        return nil
    }
}

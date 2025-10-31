//
//  Call.swift
//  UserKit
//
//  Created by Peter Nicholls on 28/7/2025.
//

import AVKit
import Foundation
import WebRTC

final class Call {
    
    // MARK: - Types
    
    struct State: Equatable, Sendable {
        var accessToken: String?
        var connectionState: ConnectionState = .disconnected
        var configuration: APIClient.ConfigurationResponse?
        var hosts: [Host] = []
        var sessionId: String?
        var transport: Transport?
        var uuid: UUID
        var url: URL?
    }
    
    // MARK: - Properties
    
    var didEnd: @Sendable (UUID) -> Void = { _ in }
    
    var accessToken: String? {
        state.accessToken
    }
    
    var uuid: UUID {
        state.uuid
    }
    
    var sessionId: String? {
        state.sessionId
    }
      
    var transport: Transport? {
        state.transport
    }
    
    let webSocketClient: WebSocketClient
    
    let apiClient: APIClient
    
    private let state: StateSync<State>
            
    private let webSocketConnectedCompleter = AsyncCompleter<Void>(label: "Web socket connect", defaultTimeout: .defaultSocketConnect)
    
    private let transportConnectedCompleter = AsyncCompleter<Void>(label: "Transport connect", defaultTimeout: .defaultTransportConnect)
    
    private lazy var user: User = .init(id: UUID().uuidString, firstName: nil, lastName: nil, call: self)
    
    private var alertController: UIAlertController? = nil
    
    private var pictureInPictureViewController: PictureInPictureViewController? = nil {
        didSet {
            pictureInPictureViewController?.delegate = self
        }
    }
    
    // MARK: - Functions
                
    init(apiClient: APIClient, uuid: UUID) {
        self.apiClient = apiClient
        self.state = .init(.init(uuid: uuid))
        self.webSocketClient = WebSocketClient()
        
        Task { @MainActor in
            AppStateListener.shared.delegates.add(delegate: self)
        }
    }
        
    func connect(accessToken: String, caller: Caller, url: URL) async throws {
        let connectionState = state.read({ $0.connectionState })
        if connectionState == .connected || connectionState == .connecting {
            return
        }
        
        state.mutate {
            $0.accessToken = accessToken
            $0.connectionState = .connecting
            $0.url = url
            $0.hosts = [Host(id: caller.id, firstName: caller.firstName, lastName: caller.lastName, call: self)]
        }
        
        webSocketConnectedCompleter.reset()
        transportConnectedCompleter.reset()
                  
        try configureAudioSession()
        
        do {
            async let sessionTask = apiClient.request(
                accessToken: accessToken,
                endpoint: .postSession(.init()),
                as: APIClient.PostSessionResponse.self
            )
            
            async let configurationTask = apiClient.request(
                accessToken: accessToken,
                endpoint: .configuration(.init()),
                as: APIClient.ConfigurationResponse.self
            )
            
            async let webSocketTask = webSocketClient.connect(
                accessToken: accessToken,
                url: url
            )

            await webSocketClient.set { [weak self] message in
                guard let self = self else { return }
                switch message {
                case .callUpdated(let data):
                    do {
                        if let participant = data?.participants.first(where: { $0.role == .user }) {
                            try await self.user.update(participant: participant)
                        }

                        let participants = data?.participants.filter { $0.role == .host } ?? []
                        for participant in participants {
                            if let host = self.state.read({ $0.hosts }).first(where: { $0.id == participant.id }) {
                                try await host.set(tracks: participant.tracks)
                            } else {
                                let host = Host(id: participant.id, firstName: participant.firstName, lastName: participant.lastName, call: self)
                                self.state.mutate { $0.hosts.append(host) }
                                try await host.set(tracks: participant.tracks)
                            }
                        }
                    } catch {
                        Logger.debug(logLevel: .error, scope: .core, error: error)
                    }
                case .ended(let data):
                    do {
                        try await end(uuid: data.uuid)
                    } catch {
                        Logger.debug(logLevel: .error, scope: .core, message: "Failed to end call")
                    }
                default:
                    break
                }
            }
            
            let (response, configuration, _) = try await (sessionTask, configurationTask, webSocketTask)

            webSocketConnectedCompleter.resume(returning: ())

            state.mutate {
                $0.connectionState = .connected
                $0.configuration = configuration
                $0.sessionId = response.sessionId
            }
        } catch {
            webSocketConnectedCompleter.resume(throwing: error)
            throw error
        }
        
        Logger.debug(logLevel: .info, scope: .core, message: "Connected to call")
            
        try await webSocketConnectedCompleter.wait(timeout: .defaultSocketConnect)
        try Task.checkCancellation()
        
        guard let accessToken = state.read({ $0.accessToken }), let configuration = state.read({ $0.configuration }), let sessionId = state.read({ $0.sessionId }) else {
            throw UserKitError.invalidState
        }
        
        let rtcConfiguration = RTCConfiguration.userKit()
        rtcConfiguration.iceServers = configuration.iceServers.map { iceServer in
            return DispatchQueue.userKitWebRTC.sync {
                RTCIceServer(
                    urlStrings: iceServer.urls,
                    username: iceServer.username,
                    credential: iceServer.credential
                )
            }
        }
        let transport = try Transport(configuration: rtcConfiguration)
        
        await transport.set { [weak self] state in
            switch state {
            case .connected:
                self?.transportConnectedCompleter.resume(returning: ())
            default:
                break
            }
        }
        
        await transport.set { [weak self] offer in
            guard let self else { return }
                            
            let tracks: [APIClient.PushTracksRequest.Track] = user.trackPublications.values.compactMap { pub in
                guard let track = pub.track, let mid = track.transceiver?.mid else {
                    return nil
                }

                return APIClient.PushTracksRequest.Track(
                    location: "local",
                    trackName: track.mediaTrack.trackId,
                    mid: mid
                )
            }

            let response = try await self.apiClient.request(
                accessToken: accessToken,
                endpoint: .pushTracks(sessionId, .init(
                    sessionDescription: .init(sdp: offer.sdp, type: RTCSessionDescription.string(for: offer.type)),
                    tracks: tracks
                )),
                as: APIClient.PushTracksResponse.self
            )
            
            try await transport.set(
                remoteDescription: .init(
                    type: RTCSessionDescription.type(for: response.sessionDescription.type),
                    sdp: response.sessionDescription.sdp
                )
            )
        }
        
        await transport.set { [weak self] peerConnection, rtpReceiver, streams in
            guard let self = self else { return }
            guard let transceiver = peerConnection.transceivers.first(where: { $0.receiver.receiverId == rtpReceiver.receiverId }) else {
                return
            }
            
            let hosts = self.state.read({ $0.hosts })
            for host in hosts {
                for (_, publication) in host.trackPublications {
                    if publication.state.read({ $0.mid }) == transceiver.mid {
                        guard let receivedTrack = rtpReceiver.track else { continue }
                        let remoteTrack = Track(name: publication.name, kind: publication.kind, source: publication.source, track: receivedTrack, isMuted: publication.isMuted)
                        await publication.set(track: remoteTrack)
                        return
                    }
                }
            }
        }

        state.mutate { $0.transport = transport }
        
        user.willStart = { [weak self] track in
            switch track.source {
            case .screenShareVideo:
                await self?.stopPictureInPicture()
                await self?.removePictureInPictureViewController()
               
                try await Task.sleep(nanoseconds: 500_000_000)
            default:
                break
            }
        }
        
        user.didStart = { [weak self] track in
            switch track.source {
            case .screenShareVideo:
                await self?.addPictureInPictureViewController()
                await self?.pictureInPictureViewController?.set(host: self?.state.hosts.first)
                await self?.pictureInPictureViewController?.set(user: self?.user)
                try await Task.sleep(nanoseconds: 500_000_000)
                await self?.startPictureInPicture()
                await self?.setPictureInPictureTrack()
                TouchIndicator.enabled = .always
            case .camera:
                await self?.pictureInPictureViewController?.set(user: self?.user)
            default:
                break
            }
        }

        user.didStop = { track in
            switch track.source {
            case .screenShareVideo:
                TouchIndicator.enabled = .never
            default:
                break
            }
        }

        try await user.setMicrophone(enabled: true)
        
        try await transportConnectedCompleter.wait(timeout: .defaultTransportConnect)
        try Task.checkCancellation()
        
        var tracks = user.trackPublications.values.map { publication in
            WebSocketClient.Message.Client.Track(
                id: "\(sessionId)/\(publication.name)",
                type: publication.source.type,
                state: (publication.track?.isMuted ?? false) ? "inactive" : "active"
            )
        }
        
        tracks.append(contentsOf: [
            WebSocketClient.Message.Client.Track(
                id: UUID().uuidString,
                type: "video",
                state: "inactive"
            ),
            WebSocketClient.Message.Client.Track(
                id: UUID().uuidString,
                type: "screenShare",
                state: "inactive"
            )
        ])
                
        try await webSocketClient.send(message: .init(type: .updateTracks, data: .updateTracks(.init(transceiverSessionId: sessionId, tracks: tracks))))
        await webSocketClient.resumeOutgoingQueue()
    }
    
    func answer() async throws {
        guard user.participantState == .none else {
            return
        }
        
        user.set(participantState: .answered)
    }
    
    func join() async throws {
        guard user.participantState == .answered else {
            return
        }
        
        user.set(participantState: .joined)
                
        async let websocketTask: Void = {
            try await webSocketConnectedCompleter.wait(timeout: .defaultSocketConnect)
            try Task.checkCancellation()
            try await transportConnectedCompleter.wait(timeout: .defaultTransportConnect)
            try Task.checkCancellation()
            try await webSocketClient.send(message: .init(type: .accept, data: .none))
            try Task.checkCancellation()
            await webSocketClient.resumeIncomingQueue()
        }()

        async let pictureInPictureTask: Void = {
            await addPictureInPictureViewController()
            await pictureInPictureViewController?.set(user: user)
            await pictureInPictureViewController?.set(host: state.hosts.first)
            await startPictureInPicture()
        }()

        _ = try await (websocketTask, pictureInPictureTask)
    }
    
    func end(uuid: UUID) async throws {
        guard state.read({ $0.uuid }) == uuid else {
            Logger.debug(logLevel: .warn, scope: .core, message: "Attempted to end call that isn't active")
            return
        }
        
        didEnd(uuid)
        
        await stopPictureInPicture()
        await removePictureInPictureViewController()
        
        try await webSocketClient.send(message: .init(type: .end, data: .end(.init(uuid: uuid))))
        await webSocketClient.disconnect()
        
        if let accessToken = accessToken, let url = state.read({ $0.url }) {
            try await self.apiClient.request(
                accessToken: accessToken,
                endpoint: .end(url, .init(type: "call.participant.end", data: .init(uuid: uuid.uuidString))),
                as: APIClient.EndResponse.self
            )
        }

        let transport = state.read { $0.transport }
        await transport?.close()
                                
        state.mutate {
            $0.accessToken = nil
            $0.connectionState = .disconnected
            $0.url = nil
            $0.sessionId = nil
            $0.transport = nil
        }
        
        await user.unpublish()
    }
    
    func transportShouldNegotiate() async throws {
        guard let transport = state.transport else {
            throw UserKitError.invalidState
        }
        
        await transport.negotiate()
    }
    
    func didActivateAudio(audioSession: AVAudioSession) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        session.audioSessionDidActivate(audioSession)
        session.isAudioEnabled = true
        session.unlockForConfiguration()
    }
    
    func didDeactivateAudio(audioSession: AVAudioSession) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        session.isAudioEnabled = false
        session.audioSessionDidDeactivate(audioSession)
        session.unlockForConfiguration()
    }
    
    private func configureAudioSession() throws {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.useManualAudio = true

        audioSession.lockForConfiguration()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetooth])
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        audioSession.unlockForConfiguration()
    }
}

extension Call {
    @MainActor
    private func addPictureInPictureViewController() async {
        guard let viewController = UIViewController.topViewController else {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to find top view controller"
            )
            return
        }
        
        guard pictureInPictureViewController == nil else {
            return
        }
    
        let pictureInPictureViewController = PictureInPictureViewController()
        self.pictureInPictureViewController = pictureInPictureViewController
                
        viewController.addChild(pictureInPictureViewController)
        viewController.view.addSubview(pictureInPictureViewController.view)
        pictureInPictureViewController.view.isUserInteractionEnabled = false
        pictureInPictureViewController.view.isHidden = false
        pictureInPictureViewController.view.frame = .init(x: viewController.view.frame.width - 1, y: viewController.view.safeAreaInsets.top, width: 1, height: 1)
        pictureInPictureViewController.didMove(toParent: viewController)
        
        viewController.view.layoutIfNeeded()
    }

    @MainActor
    private func removePictureInPictureViewController() async {
        guard let pictureInPictureViewController = pictureInPictureViewController else {
            return
        }
    
        pictureInPictureViewController.willMove(toParent: nil)
        pictureInPictureViewController.view.removeFromSuperview()
        pictureInPictureViewController.removeFromParent()
        
        self.pictureInPictureViewController = nil
    }
    
    @MainActor
    private func startPictureInPicture() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run { [weak self] in
            guard let self = self,
                  let pictureInPictureViewController = self.pictureInPictureViewController else {
                return
            }

            pictureInPictureViewController.delegate = self
            pictureInPictureViewController.pictureInPictureController.startPictureInPicture()
        }
        
        while !(await MainActor.run {
            self.pictureInPictureViewController?.pictureInPictureController.isPictureInPictureActive ?? false
        }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    @MainActor
    private func setPictureInPictureTrack() async {
        let hosts = state.read { $0.hosts }
        for host in hosts {
            for publication in host.trackPublications.values {
                if let track = publication.track, track.kind == .video, !track.isMuted, let videoTrack = track.mediaTrack as? RTCVideoTrack {
                    pictureInPictureViewController?.set(track: videoTrack)
                    return
                }
            }
        }
    }
    
    @MainActor
    private func stopPictureInPicture() async {
        await MainActor.run { [weak self] in
            guard let self = self,
                  let pictureInPictureViewController = self.pictureInPictureViewController else {
                return
            }
            
            pictureInPictureViewController.delegate = nil
            pictureInPictureViewController.pictureInPictureController.stopPictureInPicture()
        }
        
        while await MainActor.run(body: { [weak self] in
            self?.pictureInPictureViewController?.pictureInPictureController.isPictureInPictureActive ?? false
        }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

extension Call: PictureInPictureViewControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        @MainActor
        func presentAlert(title: String, message: String, options: [UIAlertAction]) {
            guard let viewController = UIViewController.topViewController else {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to find top view controller"
                )
                return
            }
            
            alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            guard let alertController = alertController else { return }
            
            options.forEach { alertAction in
                alertController.addAction(alertAction)
            }
            alertController.preferredAction = options.first
            viewController.present(alertController, animated: true)
        }
                
        await presentAlert(title: "Continue Call", message: "You are in a call with Peter", options: [
            await UIAlertAction(title: "End Call", style: .destructive) { [weak self] alertAction in
                guard let self = self else { return }
                Task {
                    try await self.end(uuid: self.uuid)
                }
            },
            UIAlertAction(title: "Continue Call", style: .cancel) { [weak self] alertAction in
                Task {
                    await self?.startPictureInPicture()
                    await self?.setPictureInPictureTrack()
                }
            },
        ])
        
        return true
    }
}

extension Call: AppStateDelegate {
    func appDidEnterBackground() {
        Task { [weak self] in
            try await self?.webSocketClient.send(message: .init(
                type: .updateParticipant,
                data: .updateParticipant(.init(appState: "background"))
            ))
        }
    }

    func appWillEnterForeground() {
        Task { [weak self] in
            try await self?.webSocketClient.send(message: .init(
                type: .updateParticipant,
                data: .updateParticipant(.init(appState: "foreground"))
            ))
        }
    }

    func appWillTerminate() {
        let uuid = state.read({ $0.uuid })

        Task.detached {
            try await self.end(uuid: uuid)
        }
    }
}

//
//  CallManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

//
//  CallManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit
import UIKit
import ReplayKit
import SwiftUI
import WebRTC

protocol CallManagerDelegate: AnyObject {
    func callManager(_ manager: CallManager, didEndCall uuid: UUID)
}

struct Call: Codable, Equatable {
    struct Participant: Codable, Equatable {
        enum State: String, Codable {
            case none
            case initialized
            case declined
            case joined
        }
        
        enum Role: String, Codable {
            case host
            case user
        }
        
        struct Track: Codable, Equatable {
            enum State: String, Codable {
                case active, requested, inactive
            }
            
            enum TrackType: String, Codable {
                case audio, video, screenShare
            }
            
            let state: State
            let id: String?
            let type: TrackType
        }

        let id: String?
        let firstName: String?
        let lastName: String?
        let state: State
        let role: Role
        let tracks: [Track]
        let transceiverSessionId: String?
        
        private enum CodingKeys: String, CodingKey {
            case id, firstName, lastName, state, role, tracks, transceiverSessionId
        }
        
        init(id: String? = nil, firstName: String? = nil, lastName: String? = nil, state: State, role: Role, tracks: [Track] = [], transceiverSessionId: String? = nil) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.state = state
            self.role = role
            self.tracks = tracks
            self.transceiverSessionId = transceiverSessionId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
            lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
            state = try container.decode(State.self, forKey: .state)
            role = try container.decode(Role.self, forKey: .role)
            tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
            transceiverSessionId = try container.decodeIfPresent(String.self, forKey: .transceiverSessionId)
        }
    }
    struct TouchIndicator: Codable, Equatable {
        enum State: String, Codable {
            case active, inactive
        }
        
        let state: State
    }
    let uuid: String
    let participants: [Participant]
    let touchIndicator: TouchIndicator
}

class CallManager {
    
    // MARK: - Types
    
    enum State: Equatable {
        case none
        case some(Call)
    }
    
    // MARK: - Properties
    
    weak var delegate: CallManagerDelegate?
        
    private let apiClient: APIClient
    
    private let webRTCClient: WebRTCClient
    
    private let webSocketClient: WebSocket
    
    private let storage: Storage
    
    private let state: StateSync<State>
    
    private var accessToken: String? {
        storage.get(AppUserCredentials.self)?.accessToken
    }
    
    private var sessionId: String? = nil
    
    private var pictureInPictureViewController: PictureInPictureViewController? = nil {
        didSet {
            pictureInPictureViewController?.delegate = self
        }
    }
    
    private var alertController: UIAlertController? = nil
    
    private let cameraClient = CameraClient()
            
    // MARK: - Functions
    
    init(apiClient: APIClient, webRTCClient: WebRTCClient, webSocketClient: WebSocket, storage: Storage) {
        self.apiClient = apiClient
        self.webRTCClient = webRTCClient
        self.webSocketClient = webSocketClient
        self.storage = storage
        self.state = .init(.none)
        
        state.onDidMutate = { [weak self] newState, oldState in
            Task {
                switch (oldState, newState) {
                case (.none, .some(let newCall)):
                    await self?.handleStateChange(oldCall: nil, newCall: newCall)
                case (.some(let oldCall), .some(let newCall)):
                    await self?.handleStateChange(oldCall: oldCall, newCall: newCall)
                case (.some(let oldCall), .none):
                    await self?.handleStateChange(oldCall: oldCall, newCall: nil)
                case (.none, .none):
                    break
                }
            }
        }
    }
    
    func update(app: UserManager.App?) {
        pictureInPictureViewController?.set(avatar: app?.iconUrl)
    }
    
    func update(call: Call?) {
        self.state.mutate {
            switch call {
            case .some(let call):
                $0 = .some(call)
            case .none:
                $0 = .none
            }
        }
    }
    
    @MainActor
    func join() async {
        guard let accessToken = accessToken else { return }

        addPictureInPictureViewController()
        
        do {
            async let apiTask = apiClient.request(
                accessToken: accessToken,
                endpoint: .postSession(.init()),
                as: APIClient.PostSessionResponse.self
            )

            configureAudioSession()

            async let webRTCTask = webRTCClient.configure()

            let (response, _) = try await (apiTask, webRTCTask)
            self.sessionId = response.sessionId
            
            Logger.debug(
                logLevel: .debug,
                scope: .core,
                message: "Joined call"
            )

        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to join call",
                error: error
            )
        }
                
        async let result = startPictureInPicture()
        async let pushTracks: Void = pushTracks()
        _ = await (result, pushTracks)
    }

    func webSocketDidConnect() {
        switch state.read({ $0 }) {
        case .some(let call) where call.participants.first(where: { $0.role == .user && $0.state == .joined }) != nil:
            break
            // What did this do?
//            Task {
//                try await updateParticipant(state: .joined)
//            }
        default:
            break
        }
    }
    
    @MainActor private func presentAlert(title: String, message: String, options: [UIAlertAction]) {
        guard let viewController = UIViewController.topViewController else {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to find top view controller"
            )
            return
        }
        
        alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        guard let alertController = alertController else { return }
        
        options.forEach { alertAction in
            alertController.addAction(alertAction)
        }
        alertController.preferredAction = options.first
        viewController.present(alertController, animated: true)
    }
    
    private func configureAudioSession() {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.lockForConfiguration()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker])
            audioSession.useManualAudio = false
            audioSession.isAudioEnabled = true
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
        } catch {
            Logger.debug(logLevel: .error, scope: .core, message: "Failed to configure audio session", error: error)
        }
        audioSession.unlockForConfiguration()
    }
    
    private func updateParticipantTracks() async throws {
        guard let sessionId = sessionId else {
            return
        }
        
        // Fetch the tracks
        let tracks: [[String: Any]] = await webRTCClient.getLocalTransceivers().compactMap { type, transceiver in
            guard let id = transceiver.sender.track?.trackId else {
                return nil
            }
            
            return [
                "id": "\(sessionId)/\(id)",
                "type": type,
                "state": type == "audio" ? "active" : "inactive"
            ]
        }
        
        // Update the participants join state
        let data: [String: Any] = [
            "transceiverSessionId": sessionId,
            "tracks": tracks
        ]
        
        let object: [String: Any] = [
            "type": "call.participant.tracks.update",
            "data": data
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: object, options: .prettyPrinted)
        guard let json = String(data: jsonData, encoding: .utf8) else {
            enum UserKitError: Error { case invalidJSON }
            throw UserKitError.invalidJSON
        }
        webSocketClient.send(string: json)
    }
    
    private func post(message: [String: Any]) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
        guard let json = String(data: jsonData, encoding: .utf8) else {
            enum UserKitError: Error { case invalidJSON }
            throw UserKitError.invalidJSON
        }
        webSocketClient.send(string: json)
    }
    
    private func end(uuid: String) async {
        await stopPictureInPicture()
        await cameraClient.stop()
        
        removePictureInPictureViewController()
        
        if RPScreenRecorder.shared().isRecording {
            RPScreenRecorder.shared().stopCapture()
        }
        TouchIndicator.enabled = .never
        
        await webRTCClient.close()
        
        do {
            let message: [String: Any] = ["type": "call.participant.end", "data": ["uuid": uuid]]
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
            guard let json = String(data: jsonData, encoding: .utf8) else {
                enum UserKitError: Error { case invalidJSON }
                throw UserKitError.invalidJSON
            }
            webSocketClient.send(string: json)
        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to end call",
                error: error
            )
        }
        
        delegate?.callManager(self, didEndCall: UUID(uuidString: uuid)!)
    }
    
    private func addPictureInPictureViewController() {
        Task { @MainActor in
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
            pictureInPictureViewController.view.frame = .init(x: viewController.view.frame.width - 50, y: viewController.view.safeAreaInsets.top, width: 50, height: 50)
            pictureInPictureViewController.didMove(toParent: viewController)
            
            viewController.view.layoutIfNeeded()
        }
    }
    
    private func removePictureInPictureViewController() {
        Task { @MainActor in
            guard let pictureInPictureViewController = pictureInPictureViewController else {
                return
            }
        
            pictureInPictureViewController.willMove(toParent: nil)
            pictureInPictureViewController.view.removeFromSuperview()
            pictureInPictureViewController.removeFromParent()
            
            self.pictureInPictureViewController = nil
        }
    }
    
    private func startPictureInPicture() async -> Bool {
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run { [weak self] in
            guard let self = self,
                  let pictureInPictureViewController = self.pictureInPictureViewController else {
                return
            }
            
            pictureInPictureViewController.pictureInPictureController.startPictureInPicture()
        }
        
        while !(await MainActor.run {
            self.pictureInPictureViewController?.pictureInPictureController.isPictureInPictureActive ?? false
        }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        return true
    }
    
    private func stopPictureInPicture() async {
        await MainActor.run { [weak self] in
            guard let self = self,
                  let pictureInPictureViewController = self.pictureInPictureViewController else {
                return
            }
            
            pictureInPictureViewController.pictureInPictureController.stopPictureInPicture()
        }
        
        while await MainActor.run(body: { [weak self] in
            self?.pictureInPictureViewController?.pictureInPictureController.isPictureInPictureActive ?? false
        }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private func pullTracks() async {
        guard let accessToken = accessToken else { return }
        
        guard let sessionId = sessionId else {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to pull tracks, no session present"
            )
            return
        }
        
        guard case .some(let call) = state.read({ $0 }) else {
            return
        }
                        
        var tracks: [APIClient.PullTracksRequest.Track] = []
        
        let participants = call.participants.filter { $0.role == .host }
        for participant in participants {
            guard let sessionId = participant.transceiverSessionId else {
                continue
            }
            
            for track in participant.tracks {
                guard let id = track.id else {
                    continue
                }
                
                let trackName = id.contains("/") ? String(id.split(separator: "/").last ?? "") : id

                tracks.append(
                    APIClient.PullTracksRequest.Track(
                        location: "remote",
                        trackName: trackName,
                        sessionId: sessionId
                    )
                )
            }
        }
        
        if tracks.isEmpty {
            return
        }
        
        do {
            let response = try await apiClient.request(
                accessToken: accessToken,
                endpoint: .pullTracks(sessionId, .init(tracks: tracks)),
                as: APIClient.PullTracksResponse.self
            )
            
            guard let sessionDescription = response.sessionDescription, response.requiresImmediateRenegotiation else {
                // TODO: Handle track errors
                return
            }
            
            try await webRTCClient.setRemoteDescription(.init(sdp: sessionDescription.sdp, type: .offer))
            let answer = try await webRTCClient.createAnswer()
            let localDescription = try await webRTCClient.setLocalDescription(answer)
            
            await setPictureInPictureTrack()
            
            try await apiClient.request(
                accessToken: accessToken,
                endpoint: .renegotiate(sessionId, .init(
                    sessionDescription: .init(sdp: localDescription.sdp, type: "answer")
                )),
                as: APIClient.RenegotiateResponse.self
            )
            
            Logger.debug(
                logLevel: .debug,
                scope: .core,
                message: "Pulled tracks",
            )
        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to pull tracks",
                error: error
            )
        }
    }
    
    private func setPictureInPictureTrack() async {
        let transceivers = await webRTCClient.transceivers()
        if let videoTrack = transceivers.filter({ $0.direction != .sendOnly }).filter({ $0.mediaType == .video }).compactMap({ $0.receiver.track as? RTCVideoTrack }).last {
            await pictureInPictureViewController?.set(track: videoTrack)
        }
    }
    
    private func pushTracks() async {
        guard let accessToken = accessToken else { return }
        
        guard let sessionId = sessionId else {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to push tracks, no session present"
            )
            return
        }
        
        guard case .some(_) = state.read({ $0 }) else {
            return
        }

        do {
            let offer = try await webRTCClient.createOffer()
            let localDescription = try await webRTCClient.setLocalDescription(offer)
            let transceivers = await webRTCClient.getLocalTransceivers()
            
            let tracks = transceivers.map { type, transceiver in
                APIClient.PushTracksRequest.Track(
                    location: "local",
                    trackName: transceiver.sender.track!.trackId,
                    mid: transceiver.mid
                )
            }
            
            if tracks.isEmpty {
                return
            }
                        
            let response = try await apiClient.request(
                accessToken: accessToken,
                endpoint: .pushTracks(sessionId, .init(
                    sessionDescription: .init(sdp: localDescription.sdp, type: "offer"),
                    tracks: tracks
                )),
                as: APIClient.PushTracksResponse.self
            )
            
            try await webRTCClient.setRemoteDescription(.init(sdp: response.sessionDescription.sdp, type: .answer))
            
            try await updateParticipantTracks()
        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "Failed to push tracks",
                error: error
            )
        }
    }
    
    private func handleStateChange(oldCall: Call?, newCall: Call?) async {
        switch (oldCall, newCall) {
        case (.none, .some):
            break
        case (.some(let oldCall), .some(let newCall)):
            guard let newUser = newCall.participants.first(where: { $0.role == .user }), newUser.state == .joined else {
                return
            }
            
            let oldUser = oldCall.participants.first(where: { $0.role == .user }) ?? .init(state: .none, role: .user)

            let oldAudioTrack = oldUser.tracks.first(where: { $0.type == .audio })
            let newAudioTrack = newUser.tracks.first(where: { $0.type == .audio })
                    
            if let oldTrack = oldAudioTrack, let newTrack = newAudioTrack {
                switch (oldTrack.state, newTrack.state) {
                case (.inactive, .requested):
                    await requestAudio()
                case (.active, .inactive):
                    await muteAudio()
                default:
                    break
                }
            }
            
            let oldVideoTrack = oldUser.tracks.first(where: { $0.type == .video })
            let newVideoTrack = newUser.tracks.first(where: { $0.type == .video })
                    
            if let oldTrack = oldVideoTrack, let newTrack = newVideoTrack {
                switch (oldTrack.state, newTrack.state) {
                case (.inactive, .requested):
                    await requestVideo()
                case (.active, .inactive):
                    await stopVideo()
                default:
                    break
                }
            }

            let oldScreenShareTrack = oldUser.tracks.first(where: { $0.type == .screenShare })
            let newScreenShareTrack = newUser.tracks.first(where: { $0.type == .screenShare })
            
            if let oldTrack = oldScreenShareTrack, let newTrack = newScreenShareTrack {
                switch (oldTrack.state, newTrack.state) {
                case (.inactive, .requested):
                    await requestScreenShare()
                case (.active, .inactive):
                    await stopScreenShare()
                default:
                    break
                }
                
                switch (newCall.touchIndicator.state, newTrack.state) {
                case (.active, .active):
                    TouchIndicator.enabled = .always
                default:
                    TouchIndicator.enabled = .never
                }
            }
                        
            let oldTracks = oldCall.participants.filter { $0.role == .host }.flatMap { $0.tracks }
            let newTracks = newCall.participants.filter { $0.role == .host }.flatMap { $0.tracks }
            
            if oldTracks != newTracks {
                await pullTracks()
            }
        case (.some(let oldCall), .none):
            await alertController?.dismiss(animated: true)
            await end(uuid: oldCall.uuid)
        case (.none, .none):
            break
        }
    }
    
    private func requestAudio() async {
        func updateParticipant(state: Call.Participant.Track.State) async {
            guard case .some(let call) = self.state.read({ $0 }) else {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle state change, invalid call state"
                )
                return
            }
            
            guard let participant = call.participants.first(where: { $0.role == .user }) else {
                return
            }
            
            let data: [String: Any] = [
                "transceiverSessionId": participant.transceiverSessionId ?? "",
                "tracks": participant.tracks.map { track in
                    [
                        "id": track.id,
                        "state": track.type == .audio ? state.rawValue : track.state.rawValue,
                        "type": track.type.rawValue
                    ]
                }
            ]
            
            let participantUpdate: [String: Any] = [
                "type": "call.participant.tracks.update",
                "data": data
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
                guard let json = String(data: jsonData, encoding: .utf8) else {
                    enum UserKitError: Error { case invalidJSON }
                    throw UserKitError.invalidJSON
                }
                webSocketClient.send(string: json)
            } catch {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle state change, JSON invalid",
                    error: error
                )
            }
        }
        
        let transceivers = await webRTCClient.getLocalTransceivers()
        if let audioTransceiver = transceivers["audio"] {
            audioTransceiver.sender.track?.isEnabled = true
        }

        await updateParticipant(state: .active)
    }

    private func muteAudio() async {
        func updateParticipant(state: Call.Participant.Track.State) async {
            guard case .some(let call) = self.state.read({ $0 }) else {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle state change, invalid call state"
                )
                return
            }
            
            guard let participant = call.participants.first(where: { $0.role == .user }) else {
                return
            }
            
            let data: [String: Any] = [
                "transceiverSessionId": participant.transceiverSessionId ?? "",
                "tracks": participant.tracks.map { track in
                    [
                        "id": track.id,
                        "state": track.type == .audio ? state.rawValue : track.state.rawValue,
                        "type": track.type.rawValue
                    ]
                }
            ]
            
            let participantUpdate: [String: Any] = [
                "type": "call.participant.tracks.update",
                "data": data
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
                guard let json = String(data: jsonData, encoding: .utf8) else {
                    enum UserKitError: Error { case invalidJSON }
                    throw UserKitError.invalidJSON
                }
                webSocketClient.send(string: json)
            } catch {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle state change, JSON invalid",
                    error: error
                )
            }
        }
        
        let transceivers = await webRTCClient.getLocalTransceivers()
        if let audioTransceiver = transceivers["audio"] {
            audioTransceiver.sender.track?.isEnabled = false
        }
        
        await updateParticipant(state: .inactive)
    }
    
    private func requestVideo() async {
        func updateParticipant(state: Call.Participant.Track.State) async {
            guard case .some(let call) = self.state.read({ $0 }) else {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle state change, invalid call state"
                )
                return
            }
            
            guard let participant = call.participants.first(where: { $0.role == .user }) else {
                return
            }
            
            let data: [String: Any] = [
                "transceiverSessionId": participant.transceiverSessionId ?? "",
                "tracks": participant.tracks.map { track in
                    [
                        "id": track.id,
                        "state": track.type == .video ? state.rawValue : track.state.rawValue,
                        "type": track.type.rawValue
                    ]
                }
            ]
            
            let participantUpdate: [String: Any] = [
                "type": "call.participant.tracks.update",
                "data": data
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
                guard let json = String(data: jsonData, encoding: .utf8) else {
                    enum UserKitError: Error { case invalidJSON }
                    throw UserKitError.invalidJSON
                }
                webSocketClient.send(string: json)
            } catch {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle state change, JSON invalid",
                    error: error
                )
            }
        }
        
        guard await cameraClient.requestAccess() else {
            await updateParticipant(state: .inactive)
            return
        }
        
        await updateParticipant(state: .active)

        await webRTCClient.replaceVideoTrack()

        let stream = await self.cameraClient.start()
        for await buffer in stream {
            await self.webRTCClient.handleVideoSourceBuffer(sampleBuffer: buffer.sampleBuffer)
        }
    }
    
    private func stopVideo() async {
        await cameraClient.stop()
        
        let transceivers = await webRTCClient.getLocalTransceivers()
        if let transceiver = transceivers["video"] {
            print("stopping track and replacing with nil")
            transceiver.sender.track?.isEnabled = false
            transceiver.sender.track = nil
        }
    }
    
    private func requestScreenShare() async {
        await MainActor.run {
            pictureInPictureViewController?.delegate = nil
        }
        await stopPictureInPicture()
        removePictureInPictureViewController()
        
        // Time for the view to be removed from the hierarchy
        try! await Task.sleep(nanoseconds: 50_000_000)
        
        func updateParticipant(state: Call.Participant.Track.State) async {
            guard case .some(let call) = self.state.read({ $0 }) else {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle state change, invalid call state"
                )
                return
            }
            
            guard let _ = call.participants.first(where: { $0.role == .user }) else {
                return
            }
            
            guard let participant = call.participants.first(where: { $0.role == .user }) else {
                return
            }
            
            let data: [String: Any] = [
                "transceiverSessionId": participant.transceiverSessionId ?? "",
                "tracks": participant.tracks.map { track in
                    [
                        "id": track.id,
                        "state": track.type == .screenShare ? state.rawValue : track.state.rawValue,
                        "type": track.type.rawValue
                    ]
                }
            ]
            
            let participantUpdate: [String: Any] = [
                "type": "call.participant.tracks.update",
                "data": data
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: participantUpdate, options: .prettyPrinted)
                guard let json = String(data: jsonData, encoding: .utf8) else {
                    enum UserKitError: Error { case invalidJSON }
                    throw UserKitError.invalidJSON
                }
                webSocketClient.send(string: json)
            } catch {
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle state change, JSON invalid",
                    error: error
                )
            }
        }
        
        do {
            let recorder = RPScreenRecorder.shared()
            recorder.isMicrophoneEnabled = false
            recorder.isCameraEnabled = false
            
            var isRecording = false
            
            let started = { [weak self] in
                guard let self = self else { return }
                
                self.addPictureInPictureViewController()
                
                // Time for the view to be added to the hierarchy
                try! await Task.sleep(nanoseconds: 500_000_000)
                
                await self.startPictureInPicture()
                await self.setPictureInPictureTrack()
                
                await updateParticipant(state: .active)
            }
            
            try await recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
                Task {
                    await self?.webRTCClient.handleScreenShareSourceBuffer(sampleBuffer: sampleBuffer)
                }
                
                if !isRecording {
                    isRecording = true
                    Task { await started() }
                }
            }
        } catch {
            let recordingError = error as NSError
            switch (recordingError.domain, recordingError.code) {
            case (RPRecordingErrorDomain, -5801):
                await updateParticipant(state: .inactive)
    
            default:
                Logger.debug(
                    logLevel: .error,
                    scope: .core,
                    message: "Failed to handle video request",
                    error: error
                )
            }
        }
    }
    
    private func stopScreenShare() async {
        let recorder = RPScreenRecorder.shared()
        if recorder.isRecording {
            recorder.stopCapture()
        }
        
        TouchIndicator.enabled = .never
    }
}

extension CallManager: PictureInPictureViewControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        guard case .some(let call) = state.read({ $0 }) else {
            return true
        }

        let name = call.participants.first(where: { $0.role == .host})?.firstName
        let message = "You are in a call with \(name ?? "someone")"

        await MainActor.run {
            presentAlert(title: "Continue Call", message: message, options: [
                UIAlertAction(title: "Continue", style: .default) { [weak self] alertAction in
                    Task {
                        await self?.startPictureInPicture()
                        await self?.setPictureInPictureTrack()
                    }
                },
                UIAlertAction(title: "End", style: .cancel) { [weak self] alertAction in
                    Task {
                        await self?.end(uuid: call.uuid)
                    }
                }
            ])
        }
        
        return true
    }
}

//
//  CallKitManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 7/3/2025.
//

import AVKit
import CallKit
import WebRTC

final class CallKitManager: NSObject, @unchecked Sendable {

    // MARK: - Type

    struct Call: Sendable {
        let uuid: UUID
        let url: URL
    }

    // MARK: - Callbacks

    var onAnswer: @Sendable (Call) -> Void = { _ in }
    var onEnd: @Sendable (Call) -> Void = { _ in }
    var didActivateAudio: @Sendable (AVAudioSession) -> Void = { _ in }
    var didDeactivateAudio: @Sendable (AVAudioSession) -> Void = { _ in }

    // MARK: - Properties

    private let provider: CXProvider
    private let callController: CXCallController
    private var calls: [UUID: Call] = [:]
    private let options: UserKitOptions

    // MARK: - Initialization

    init(options: UserKitOptions) {
        self.options = options

        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.supportedHandleTypes = [.generic]
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1

        self.provider = CXProvider(configuration: configuration)
        self.callController = CXCallController()

        super.init()

        guard options.callKit.enabled else {
            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "CallKit disabled, skipping delegate setup"
            )
            return
        }

        provider.setDelegate(self, queue: .main)
    }

    // MARK: - Public Methods

    func reportIncomingCall(uuid: UUID, url: URL, caller: String, hasVideo: Bool = true) {
        let call = Call(uuid: uuid, url: url)
        calls[uuid] = call

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: caller)
        update.hasVideo = hasVideo
        update.localizedCallerName = caller

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                self?.calls.removeValue(forKey: uuid)
                Logger.debug(
                    logLevel: .error,
                    scope: .pushKit,
                    message: "Failed to report incoming call",
                    info: [
                        "uuid": uuid.uuidString,
                        "url": url,
                        "caller": caller
                    ],
                    error: error
                )
            } else {
                Logger.debug(
                    logLevel: .info,
                    scope: .pushKit,
                    message: "Successfully reported incoming call",
                    info: [
                        "uuid": uuid.uuidString,
                        "caller": caller
                    ]
                )
            }
        }
    }

    @MainActor
    func endCall(uuid: UUID) async {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        do {
            try await callController.request(transaction)
            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "Successfully ended call",
                info: ["uuid": uuid.uuidString]
            )
        } catch {
            Logger.debug(
                logLevel: .error,
                scope: .pushKit,
                message: "Failed to end call",
                info: ["uuid": uuid.uuidString],
                error: error
            )
        }
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "CallKit provider did reset"
        )
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "User answered call",
            info: ["uuid": action.callUUID.uuidString]
        )

        guard let call = calls[action.callUUID] else {
            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "Call data not found",
                info: ["uuid": action.callUUID.uuidString]
            )
            action.fail()
            return
        }
        
        onAnswer(call)
        
        // TODO: - This should be fulfilled unless WS fails to connect
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "User ended call",
            info: ["uuid": action.callUUID.uuidString]
        )

        guard let call = calls[action.callUUID] else {
            Logger.debug(
                logLevel: .info,
                scope: .pushKit,
                message: "Call data not found",
                info: ["uuid": action.callUUID.uuidString]
            )
            action.fulfill()
            return
        }

        onEnd(call)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "CallKit activated audio session"
        )
        
        didActivateAudio(audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "CallKit deactivated audio session"
        )
        
        didDeactivateAudio(audioSession)
    }
}

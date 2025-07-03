//
//  CallKitManager.swift
//  UserKit
//
//  Created by Peter Nicholls on 7/3/2025.
//

import AVKit
import CallKit
import UIKit

protocol CallKitManagerDelegate: AnyObject {
    func callKitManager(_ manager: CallKitManager, didAnswerCall callUUID: UUID)
    func callKitManager(_ manager: CallKitManager, didEndCall callUUID: UUID)
}

class CallKitManager: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: CallKitManagerDelegate?
    
    private let provider: CXProvider
    private let callController: CXCallController
    
    // MARK: - Initialization
    
    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.supportedHandleTypes = [.generic]
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        
        self.provider = CXProvider(configuration: configuration)
        self.callController = CXCallController()
        super.init()
        
        provider.setDelegate(self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    func reportIncomingCall(uuid: UUID, handle: String, hasVideo: Bool = true) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = hasVideo
        update.localizedCallerName = handle
        
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                Logger.debug(
                    logLevel: .error,
                    scope: .pushKit,
                    message: "Failed to report incoming call",
                    info: [
                        "callUUID": uuid.uuidString,
                        "handle": handle
                    ],
                    error: error
                )
            } else {
                Logger.debug(
                    logLevel: .info,
                    scope: .pushKit,
                    message: "Successfully reported incoming call",
                    info: [
                        "callUUID": uuid.uuidString,
                        "handle": handle
                    ]
                )
            }
        }
    }
    
    func endCall(uuid: UUID) {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callController.request(transaction) { [weak self] error in
            if let error = error {
                Logger.debug(
                    logLevel: .error,
                    scope: .pushKit,
                    message: "Failed to end call",
                    info: [
                        "callUUID": uuid.uuidString
                    ],
                    error: error
                )
            } else {
                Logger.debug(
                    logLevel: .info,
                    scope: .pushKit,
                    message: "Successfully ended call",
                    info: [
                        "callUUID": uuid.uuidString
                    ]
                )
            }
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
            info: [
                "callUUID": action.callUUID.uuidString
            ]
        )
        
        delegate?.callKitManager(self, didAnswerCall: action.callUUID)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "User ended call",
            info: [
                "callUUID": action.callUUID.uuidString
            ]
        )
        
        delegate?.callKitManager(self, didEndCall: action.callUUID)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "CallKit activated audio session"
        )
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Logger.debug(
            logLevel: .info,
            scope: .pushKit,
            message: "CallKit deactivated audio session"
        )
    }
}

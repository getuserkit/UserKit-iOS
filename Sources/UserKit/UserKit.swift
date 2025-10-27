//
//  File.swift
//
//
//  Created by Peter Nicholls on 3/9/2024.
//

import Foundation
import UIKit
import SwiftUI

internal let sdkVersion = """
1.0.0
"""

@objcMembers
public final class UserKit: NSObject {
    
    // MARK: - Properties
    
    @objc(sharedInstance)
    public static var shared: UserKit {
        guard let userKit = userKit else {
            Logger.debug(
                logLevel: .error,
                scope: .core,
                message: "UserKit has not been configured. Please call UserKit.configure()"
            )
            assertionFailure("UserKit has not been configured. Please call UserKit.configure()")
            return UserKit(apiKey: "")
        }
        
        return userKit
    }
    
    public var isIdentified: Bool {
        return userManager.isIdentified
    }
    
    public var logLevel: LogLevel {
        get {
            return options.logging.level
        }
        set {
            options.logging.level = newValue
        }
    }
    
    var options: UserKitOptions {
      return configManager.options
    }
    
    private static var userKit: UserKit?

    @DispatchQueueBacked
    public private(set) static var isInitialized = false
    
    private let apiKey: String
    
    private let apiClient: APIClient
        
    private let callManager: CallManager
    
    private let configManager: ConfigManager
    
    private let device: Device
    
    private let storage: Storage
    
    private let userManager: UserManager
            
    private let pushKitManager: PushKitManager
    
    private let callKitManager: CallKitManager
        
    // MARK: - Functions
    
    @discardableResult
    public static func configure(apiKey: String, options: UserKitOptions? = nil, completion: (() -> Void)? = nil) -> UserKit {
        guard userKit == nil else {
            Logger.debug(
                logLevel: .warn,
                scope: .core,
                message:
                    "UserKit.configure called multiple times. Please make sure you only call this once on app launch."
            )
            completion?()
            return shared
        }
        
        userKit = UserKit(apiKey: apiKey, options: options, completion: completion)

        Logger.debug(
            logLevel: .debug,
            scope: .core,
            message: "SDK Version - \(sdkVersion)"
        )
        
        isInitialized = true
        
        if (userKit?.isIdentified ?? false) {
            userKit?.pushKitManager.register()
        }
                
        return shared
    }
        
    init(apiKey: String, options: UserKitOptions? = nil) {
        self.apiKey = apiKey
        self.device = Device()
        let options = options ?? UserKitOptions()
        self.apiClient = APIClient(device: device)
        self.configManager = ConfigManager(options: options)
        self.storage = Storage()
        self.pushKitManager = PushKitManager(options: options)
        self.callKitManager = CallKitManager(options: options)
        self.callManager = CallManager(apiClient: apiClient, storage: storage)
        self.userManager = UserManager(apiClient: apiClient, storage: storage)
        
        super.init()
        
        callManager.didEnd = { [weak self] uuid in
            Task { await self?.callKitManager.endCall(uuid: uuid) }
        }
        
        pushKitManager.onTokenUpdate = { [weak self] data in
            Task { await self?.userManager.registerToken(data) }
        }
        
        pushKitManager.onTokenInvalidated = {
            // NOP
        }
        
        pushKitManager.didReceiveIncomingPush = { [weak self] payload in
            switch payload.call.state {
            case .ringing:
                self?.callKitManager.reportIncomingCall(
                    uuid: payload.call.uuid,
                    url: payload.call.url,
                    caller: payload.call.caller.name
                )

                Task {
                    await self?.callManager.connect(
                        caller: payload.call.caller,
                        uuid: payload.call.uuid,
                        url: payload.call.url
                    )
                }
            case .ended:
                Task {
                    await self?.callManager.end(uuid: payload.call.uuid)
                    await self?.callKitManager.endCall(uuid: payload.call.uuid)
                }
            }
        }
        
        callKitManager.onAnswer = { [weak self] call in
            Task {
                await self?.callManager.answer(uuid: call.uuid)
            }
        }

        callKitManager.onEnd = { [weak self] call in
            Task {
                await self?.callManager.end(uuid: call.uuid)
            }
        }
        
        callKitManager.didActivateAudio = { [weak self] audioSession in
            Task {
                self?.callManager.didActivateAudio(audioSession: audioSession)
            }
        }
        
        callKitManager.didDeactivateAudio = { [weak self] audioSession in
            Task {
                self?.callManager.didDeactivateAudio(audioSession: audioSession)
            }
        }
    }
    
    private convenience init(apiKey: String, options: UserKitOptions? = nil, completion: (() -> Void)?) {
        self.init(apiKey: apiKey, options: options)
        completion?()
    }
    
    @discardableResult
    @available(swift, obsoleted: 1.0)
    public static func configure(apiKey: String) -> UserKit {
        return objcConfigure(apiKey: apiKey)
    }
    
    public func identify(id: String, name: String?, email: String?) {
        Task {
            await userManager.identify(apiKey: apiKey, id: id, name: name, email: email)
            pushKitManager.register()
        }
    }
    
    public func reset() {
        Task { await userManager.reset() }
    }
    
    public func enqueue(reason: String? = nil, preferredCallTime: String? = nil) {
        Task {
            await userManager.enqueue(reason: reason, preferredCallTime: preferredCallTime)
        }
    }
    
    private static func objcConfigure(apiKey: String, options: UserKitOptions? = nil, completion: (() -> Void)? = nil) -> UserKit {
        guard userKit == nil else {
            Logger.debug(
                logLevel: .warn,
                scope: .core,
                message:
                    "UserKit.configure called multiple times. Please make sure you only call this once on app launch."
            )
            completion?()
            return shared
        }

        let options = options ?? UserKitOptions()
        userKit = UserKit(apiKey: apiKey, options: options, completion: completion)
        
        return shared
    }
}

struct RootView: View {
    var body: some View {
        EmptyView()
    }
}

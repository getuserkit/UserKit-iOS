//
//  File.swift
//
//
//  Created by Peter Nicholls on 3/9/2024.
//

import Foundation
import UIKit
import SwiftUI

let sdkVersion = """
0.1.0
"""

@objcMembers
public final class UserKit: NSObject {
    
    // MARK: - Types
    
    public enum Availability {
        case active, inactive
    }
    
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
    
    public var isLoggedIn: Bool {
        return userManager.isLoggedIn
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
    
    private let availabilityManager: AvailabilityManager
    
    private let callManager: CallManager
    
    private let configManager: ConfigManager
    
    private let device: Device
    
    private let storage: Storage
    
    private let userManager: UserManager
    
    private let webRTCClient: WebRTCClient
    
    private let webSocket: WebSocket
    
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

        return shared
    }
        
    init(apiKey: String, options: UserKitOptions? = nil) {
        self.apiKey = apiKey
        self.device = Device()
        let options = options ?? UserKitOptions()
        self.apiClient = APIClient(device: device)
        self.configManager = ConfigManager(options: options)
        self.storage = Storage()
        self.webRTCClient = WebRTCClient()
        self.webSocket = WebSocket()
        self.pushKitManager = PushKitManager()
        self.callKitManager = CallKitManager()
        self.availabilityManager = AvailabilityManager(apiClient: apiClient, storage: storage)
        self.callManager = CallManager(apiClient: apiClient, webRTCClient: webRTCClient, webSocketClient: webSocket)
        self.userManager = UserManager(apiClient: apiClient, callKitManager: callKitManager, callManager: callManager, pushKitManager: pushKitManager, storage: storage, webSocket: webSocket)
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
    
    public func identify(id: String?, name: String?, email: String?) {
        Task {
            await userManager.identify(apiKey: apiKey, id: id, name: name, email: email)
        }
    }
    
    public func availability() async throws -> Availability {
        try await availabilityManager.availability()
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

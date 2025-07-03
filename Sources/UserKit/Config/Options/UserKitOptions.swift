//
//  UserKitOptions.swift
//  UserKit
//
//  Created by Peter Nicholls on 17/6/2025.
//

import Foundation

/// Options for configuring UserKit
///
/// Pass an instance of this class to
/// ``UserKit/configure(apiKey:options:completion:)
@objc(UKUserKitOptions)
@objcMembers
public final class UserKitOptions: NSObject, Encodable {
    /// Configuration for printing to the console.
    @objc(UKLogging)
    @objcMembers
    public final class Logging: NSObject, Encodable {
        /// Defines the minimum log level to print to the console. Defaults to `info`.
        public var level: LogLevel = .info

        /// Defines the scope of logs to print to the console. Defaults to .all.
        public var scopes: Set<LogScope> = [.all]

        private enum CodingKeys: String, CodingKey {
            case logLevel
            case logScopes
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(level, forKey: .logLevel)
            try container.encode(scopes, forKey: .logScopes)
        }
    }
  
    /// Configuration for VoIP push notifications.
    @objc(UKPushKit)
    @objcMembers
    public final class PushKit: NSObject, Encodable {
        /// Enable VoIP push notifications. Defaults to `true`.
        public var enabled: Bool = true
        
        private enum CodingKeys: String, CodingKey {
            case enabled
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
        }
    }
  
    /// The log scope and level to print to the console.
    public var logging = Logging()
    
    /// Configuration for CallKit integration.
    @objc(UKCallKit)
    @objcMembers
    public final class CallKit: NSObject, Encodable {
        /// Enable CallKit integration for native call UI. Defaults to `true`.
        public var enabled: Bool = true
        
        private enum CodingKeys: String, CodingKey {
            case enabled
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
        }
    }
  
    /// VoIP push notification configuration.
    public var pushKit = PushKit()
    
    /// CallKit integration configuration.
    public var callKit = CallKit()
}

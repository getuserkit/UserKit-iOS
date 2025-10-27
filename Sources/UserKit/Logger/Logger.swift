//
//  Logger.swift
//  UserKit
//
//  Created by Peter Nicholls on 16/6/2025.
//

import Foundation

protocol Loggable {
    static func shouldPrint(logLevel: LogLevel, scope: LogScope) -> Bool
    static func debug(logLevel: LogLevel, scope: LogScope, message: String?, info: [String: Any]?, error: Swift.Error?)
}

extension Loggable {
    static func debug(logLevel: LogLevel, scope: LogScope, message: String? = nil, info: [String: Any]? = nil, error: Swift.Error? = nil) {
        debug(logLevel: logLevel, scope: scope, message: message, info: info, error: error)
    }
}

enum Logger: Loggable {
    static func shouldPrint(logLevel: LogLevel, scope: LogScope) -> Bool {
        var logging: UserKitOptions.Logging

        if UserKit.isInitialized {
            logging = UserKit.shared.options.logging
        } else {
            logging = .init()
        }
        
        if logging.level == .none {
            return false
        }
        
        let exceedsCurrentLogLevel = logLevel.rawValue >= logging.level.rawValue
        let isInScope = logging.scopes.contains(scope)
        let allLogsActive = logging.scopes.contains(.all)

        return exceedsCurrentLogLevel && (isInScope || allLogsActive)
    }

    static func debug(logLevel: LogLevel, scope: LogScope, message: String? = nil, info: [String: Any]? = nil, error: Swift.Error? = nil) {
        Task.detached(priority: .utility) {
            var output: [String] = []
            var dumping: [String: Any] = [:]

            if let message = message {
                output.append(message)
            }

            if let info = info {
                output.append(info.debugDescription)
                dumping["info"] = info
            }

            if let error = error {
                output.append(error.safeLocalizedDescription)
                dumping["error"] = error
            }

            guard shouldPrint(logLevel: logLevel, scope: scope) else {
                return
            }

            var name = "\(Date().isoString) \(logLevel.descriptionEmoji) [UserKit] [\(scope.description)] - \(logLevel.description)"

            if let message = message {
                name += ": \(message)"
            }

            if dumping.isEmpty {
                print(name)
            } else {
                dump(dumping, name: name, indent: 0, maxDepth: 100, maxItems: 100)
            }
        }
    }
}

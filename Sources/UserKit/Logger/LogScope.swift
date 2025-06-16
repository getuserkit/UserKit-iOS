//
//  LogScope.swift
//  UserKit
//
//  Created by Peter Nicholls on 16/6/2025.
//

import Foundation

/// The possible scope of logs to print to the console.
@objc(UKLogScope)
public enum LogScope: Int, Encodable, Sendable, CustomStringConvertible {
    case all, core, network

    public var description: String {
        switch self {
        case .all:
            return "all"
        case .core:
            return "core"
        case .network:
            return "network"
        }
    }
}

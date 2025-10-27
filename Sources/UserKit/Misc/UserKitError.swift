//
//  UserKitError.swift
//  UserKit
//
//  Created by Peter Nicholls on 28/7/2025.
//

import Foundation

enum UserKitError: LocalizedError {
    case cancelled
    case timedOut
    case invalidState
    case deviceNotFound
    case captureFormatNotFound
    case unableToResolveFPSRange
    case webRTC
}

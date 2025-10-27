//
//  DispatchQueue.swift
//  UserKit
//
//  Created by Peter Nicholls on 20/7/2025.
//

import Foundation

public extension DispatchQueue {
    // The queue which SDK uses to invoke WebRTC methods
    static let userKitWebRTC = DispatchQueue(label: "UserKit.webRTC", qos: .default)
}

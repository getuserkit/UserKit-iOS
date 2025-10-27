//
//  RTCConfiguration.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation
import WebRTC

extension RTCConfiguration {
    static func userKit() -> RTCConfiguration {
        let result = DispatchQueue.userKitWebRTC.sync { RTCConfiguration() }
        result.sdpSemantics = .unifiedPlan
        result.continualGatheringPolicy = .gatherContinually
        result.candidateNetworkPolicy = .all
        result.tcpCandidatePolicy = .enabled
        result.bundlePolicy = .maxBundle
        result.iceServers = [RTCIceServer(urlStrings: ["stun:stun.cloudflare.com:3478"])]
        return result
    }
}

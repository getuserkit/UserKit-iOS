//
//  LocalTrack.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

protocol LocalTrack where Self: Track {
    func mute() async throws
    func unmute() async throws
}

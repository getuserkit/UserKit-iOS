//
//  CameraCaptureOptions.swift
//  UserKit
//
//  Created by Peter Nicholls on 30/7/2025.
//

@preconcurrency import AVFoundation
import Foundation

final class CameraCaptureOptions: NSObject, VideoCaptureOptions, Sendable {
    
    // MARK: - Properties
    
    let dimensions: Dimensions
    
    let fps: Int

    override init() {
        dimensions = .h540_169
        fps = 30
    }
}

//
//  TimeInterval.swift
//  UserKit
//
//  Created by Peter Nicholls on 28/7/2025.
//

import Foundation

extension TimeInterval {
    static let defaultCallConnect: Self = 10
    static let defaultSocketConnect: Self = 10
    static let defaultTransportConnect: Self = 10
    static let defaultJoinResponse: Self = 7
}

extension TimeInterval {
    var toDispatchTimeInterval: DispatchTimeInterval {
        .milliseconds(Int(self * 1000))
    }
}

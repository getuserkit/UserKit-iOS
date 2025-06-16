//
//  DispatchQueueBacked.swift
//  UserKit
//
//  Created by Peter Nicholls on 17/6/2025.
//

import Foundation

/// A property wrapper that synchronizes access to its value with
/// a `DispatchQueue`.
@propertyWrapper
public final class DispatchQueueBacked<T>: @unchecked Sendable {
    private var value: T
    private let queue: DispatchQueue

    public init(wrappedValue: T) {
        self.value = wrappedValue
        self.queue = DispatchQueue(label: "com.userkit.\(UUID().uuidString)")
    }

    public var wrappedValue: T {
        get {
            queue.sync {
                value
            }
        }
        set {
            queue.async { [weak self] in
                self?.value = newValue
            }
        }
    }
}


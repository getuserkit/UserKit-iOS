//
//  Locks.swift
//  UserKit
//
//  Created by Peter Nicholls on 20/7/2025.
//

import Foundation
import os

#if canImport(Synchronization)
import Synchronization
#endif

/// Protocol for synchronization primitives that can execute code within a critical section.
protocol Lock {
    /// Executes the provided closure within a critical section.
    /// - Parameter fnc: The closure to execute within the lock.
    /// - Returns: The value returned by the closure.
    func sync<Result>(_ fnc: () throws -> Result) rethrows -> Result
}

/// Creates the safest/most efficient lock available for the current platform.
func createLock() -> some Lock {
    #if canImport(Synchronization)
    if #available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *) {
        return MutexWrapper()
    }
    #endif

    if #available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *) {
        return OSAllocatedUnfairLock()
    }

    return UnfairLock()
}

// MARK: - Mutex

#if canImport(Synchronization)
@available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, *)
private final class MutexWrapper: Lock {
    private let _mutex = Mutex(())

    @inline(__always)
    func sync<Result>(_ fnc: () throws -> Result) rethrows -> Result {
        try _mutex.withLock { _ in
            try fnc() // skip inout sending () parameter
        }
    }
}
#endif

// MARK: - OSAllocatedUnfairLock

@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
extension OSAllocatedUnfairLock: Lock where State == () {
    @inline(__always)
    func sync<Result>(_ fnc: () throws -> Result) rethrows -> Result {
        try withLockUnchecked(fnc) // do not check for Sendable fnc
    }
}

// MARK: - Unfair lock

//
// Read http://www.russbishop.net/the-law for more information on why this is necessary
//
private final class UnfairLock: Lock {
    private let _lock: UnsafeMutablePointer<os_unfair_lock>

    init() {
        _lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        _lock.initialize(to: os_unfair_lock())
    }

    deinit {
        _lock.deinitialize(count: 1)
        _lock.deallocate()
    }

    @inline(__always)
    func sync<Result>(_ fnc: () throws -> Result) rethrows -> Result {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return try fnc()
    }
}

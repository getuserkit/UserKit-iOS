//
//  AsyncDebounce.swift
//  UserKit
//
//  Created by Peter Nicholls on 21/7/2025.
//

import Foundation

actor Debounce {
    private var _task: Task<Void, Never>?
    private let _delay: TimeInterval

    init(delay: TimeInterval) {
        _delay = delay
    }

    deinit {
        _task?.cancel()
    }

    func cancel() {
        _task?.cancel()
    }

    func schedule(_ action: @Sendable @escaping () async throws -> Void) {
        _task?.cancel()
        _task = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(self._delay * 1_000_000_000))
            if !Task.isCancelled {
                try? await action()
            }
        }
    }
}

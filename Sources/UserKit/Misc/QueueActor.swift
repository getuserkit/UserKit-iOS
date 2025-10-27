//
//  QueueActor.swift
//  UserKit
//
//  Created by Peter Nicholls on 20/7/2025.
//

import Foundation

actor QueueActor<T: Sendable> {
    typealias OnProcess = @Sendable (T) async -> Void

    // MARK: - Public

    public enum State: Sendable {
        case resumed
        case suspended
    }

    public private(set) var state: State = .suspended

    public var count: Int { queue.count }

    // MARK: - Private

    private var queue = [T]()
    private let onProcess: OnProcess

    init(onProcess: @escaping OnProcess) {
        self.onProcess = onProcess
    }

    /// Mark as `.suspended`.
    func suspend() {
        state = .suspended
    }

    /// Only process if `.resumed` state, otherwise enqueue.
    func processIfResumed(_ value: T, or condition: Bool = false, elseEnqueue: Bool = true) async {
        await process(value, if: state == .resumed || condition, elseEnqueue: elseEnqueue)
    }

    /// Only process if `condition` is true, otherwise enqueue.
    func process(_ value: T, if condition: Bool, elseEnqueue: Bool = true) async {
        if condition {
            await onProcess(value)
        } else if elseEnqueue {
            queue.append(value)
        }
    }

    func clear() {
        if !queue.isEmpty {
            Logger.debug(logLevel: .debug, scope: .core, message: "Clearing queue which is not empty")
        }

        queue.removeAll()
        state = .suspended
    }

    /// Mark as `.resumed` and process each element with an async `block`.
    func resume() async {
        state = .resumed
        if queue.isEmpty { return }
        for element in queue {
            // Check cancellation before processing next block...
            // try Task.checkCancellation()
            await onProcess(element)
        }
        queue.removeAll()
    }
}

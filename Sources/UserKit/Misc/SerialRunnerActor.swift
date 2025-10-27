//
//  SerialRunnerActor.swift
//  UserKit
//
//  Created by Peter Nicholls on 20/7/2025.
//

import Foundation

actor SerialRunnerActor<Value: Sendable> {
    private var previousTask: Task<Value, Error>?

    func run(block: @Sendable @escaping () async throws -> Value) async throws -> Value {
        let task = Task { [previousTask] in
            // Wait for the previous task to complete, but cancel it if needed
            if let previousTask, !Task.isCancelled {
                // If previous task is still running, wait for it
                _ = try? await previousTask.value
            }

            // Check for cancellation before running the block
            try Task.checkCancellation()

            // Run the new block
            return try await block()
        }

        previousTask = task

        return try await withTaskCancellationHandler {
            // Await the current task's result
            try await task.value
        } onCancel: {
            // Ensure the task is canceled when requested
            task.cancel()
        }
    }
}

//
//  WebSocket.swift
//  UserKit
//
//  Created by Peter Nicholls on 28/7/2025.
//

import Foundation

typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>

final class WebSocket: NSObject, @unchecked Sendable, AsyncSequence, URLSessionWebSocketDelegate {
    
    // MARK: - Types
    
    enum WebSocketError: LocalizedError {
        case canceled
        case invalidState
        case unknown
    }
    
    typealias AsyncIterator = WebSocketStream.Iterator
    
    typealias Element = URLSessionWebSocketTask.Message
    
    // MARK: - Properties
    
    private let _state = StateSync(State())

    private struct State {
        var streamContinuation: WebSocketStream.Continuation?
        var connectContinuation: CheckedContinuation<Void, Error>?
    }

    private let request: URLRequest
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(60)
        config.timeoutIntervalForResource = TimeInterval(604_800)
        config.shouldUseExtendedBackgroundIdleMode = true
        config.networkServiceType = .callSignaling
        #if os(iOS) || os(visionOS)
        /// https://developer.apple.com/documentation/foundation/urlsessionconfiguration/improving_network_reliability_using_multipath_tcp
        config.multipathServiceType = .handover
        #endif
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private lazy var task: URLSessionWebSocketTask = urlSession.webSocketTask(with: request)

    private lazy var stream: WebSocketStream = WebSocketStream { continuation in
        _state.mutate { state in
            state.streamContinuation = continuation
        }
        waitForNextValue()
    }
    
    // MARK: - Functions

    init(accessToken: String, url: URL) async throws {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: .defaultSocketConnect)
        request.addValue(accessToken, forHTTPHeaderField: "Authorization")

        self.request = request
        
        super.init()
        
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                _state.mutate { state in
                    state.connectContinuation = continuation
                }
                task.resume()
            }
        } onCancel: {
            // Cancel(reset) when Task gets cancelled
            close()
        }
    }

    deinit {
        close()
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        urlSession.finishTasksAndInvalidate()

        _state.mutate { state in
            state.connectContinuation?.resume(throwing: WebSocketError.canceled)
            state.connectContinuation = nil
            state.streamContinuation?.finish(throwing: WebSocketError.canceled)
            state.streamContinuation = nil
        }
    }

    // MARK: - AsyncSequence

    func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }

    private func waitForNextValue() {
        guard task.closeCode == .invalid else {
            _state.mutate { state in
                state.streamContinuation?.finish(throwing: WebSocketError.invalidState)
                state.streamContinuation = nil
            }
            return
        }

        task.receive(completionHandler: { [weak self] result in
            guard let self, let continuation = _state.streamContinuation else {
                return
            }

            do {
                let message = try result.get()
                continuation.yield(message)
                waitForNextValue()
            } catch {
                _state.mutate { state in
                    state.streamContinuation?.finish(throwing: error)
                    state.streamContinuation = nil
                }
            }
        })
    }

    // MARK: - Send

    public func send(data: Data) async throws {
        let message = URLSessionWebSocketTask.Message.data(data)
        try await task.send(message)
    }
    
    public func send(string: String) async throws {
        let message = URLSessionWebSocketTask.Message.string(string)
        try await task.send(message)
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_: URLSession, webSocketTask _: URLSessionWebSocketTask, didOpenWithProtocol _: String?) {
        _state.mutate { state in
            state.connectContinuation?.resume()
            state.connectContinuation = nil
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        Logger.debug(
            logLevel: .debug,
            scope: .network,
            message: "WebSocket did complete",
            info: [
                "error": String(describing: error)
            ]
        )

        _state.mutate { state in
            if let error {
                state.connectContinuation?.resume(throwing: error)
                state.streamContinuation?.finish(throwing: error)
            } else {
                state.connectContinuation?.resume()
                state.streamContinuation?.finish()
            }

            state.connectContinuation = nil
            state.streamContinuation = nil
        }
    }
}

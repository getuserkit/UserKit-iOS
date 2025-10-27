//
//  WebSocketClient.swift
//  UserKit
//
//  Created by Peter Nicholls on 28/7/2025.
//

import Foundation

actor WebSocketClient {
    
    // MARK: - Types
    
    struct State {
        var connectionState: ConnectionState = .disconnected
        var socket: WebSocket?
        var messageLoopTask: Task<Void, Never>?
    }
    
    enum ConnectResponse: Sendable {
        case connected
        case reconnected
    }
    
    typealias HandleMessage = @Sendable (Message.Server) async -> Void
    
    // MARK: - Properties
    
    var handleMessage: HandleMessage?
    
    private let state = StateSync(State())
    
    private lazy var outgoingQueue = QueueActor<Message.Client>(onProcess: { [weak self] message in
        guard let self else { return }

        do {
            let webSocket = try await requireWebSocket()
            try await webSocket.send(string: message.toJSON())
            
            Logger.debug(logLevel: .debug, scope: .network, message: "Message Sent", info: ["message": message])
        } catch {
            Logger.debug(logLevel: .warn, scope: .network, message: "Failed to send queued request", error: error)
        }
    })
    
    private lazy var incomingQueue = QueueActor<Message.Server>(onProcess: { [weak self] message in
        guard let self else { return }

        await handle(message: message)
    })
    
    private let connectResponseCompleter = AsyncCompleter<ConnectResponse>(label: "Join response", defaultTimeout: .defaultJoinResponse)

    // MARK: - Functions

    func set(handleMessage block: @escaping HandleMessage) {
        self.handleMessage = block
    }
    
    @discardableResult
    func connect(accessToken: String, url: URL) async throws -> ConnectResponse {
        connectResponseCompleter.reset()

        state.mutate { $0.connectionState = .connecting }
        
        do {
            let socket = try await WebSocket(accessToken: accessToken, url: url)

            let task = Task.detached {
                Logger.debug(logLevel: .info, scope: .network, message: "Did enter WebSocket message loop...")
                
                do {
                    for try await message in socket {
                        await self.handle(message: message)
                    }
                } catch {
                    await self.disconnect(withError: error)
                }
            }
            state.mutate { $0.messageLoopTask = task }

            let connectResponse = try await connectResponseCompleter.wait()
            try Task.checkCancellation()

            state.mutate {
                $0.socket = socket
                $0.connectionState = .connected
            }
            
            return connectResponse
        } catch {
            await disconnect(withError: error)
            throw error
        }
    }
    
    func send(message: Message.Client) async throws {
        let connectionState = state.read { $0.connectionState }
        guard connectionState != .disconnected else {
            Logger.debug(logLevel: .warn, scope: .network, message: "Attempting to send web socket message whilst disconnected")
            throw UserKitError.invalidState
        }
        
        await outgoingQueue.processIfResumed(message, or: !message.enqueue(), elseEnqueue: message.enqueue())
    }
    
    private func handle(message: URLSessionWebSocketTask.Message) async {
        let webSocketMessage = message
        
        var message: Message.Server?
        switch webSocketMessage {
        case .data(let data):
            message = try? Message.Server.from(data: data)
        case .string(let string):
            guard let data = string.data(using: .utf8) else { return }
            message = try! Message.Server.from(data: data)
        default:
            message = nil
        }
        
        guard let message else {
            Logger.debug(logLevel: .warn, scope: .network, message: "Failed to decode web socket message")
            return
        }

        Task.detached {
            switch message {
            default:
                await self.incomingQueue.processIfResumed(message, or: !message.enqueue())
            }
        }
    }
    
    private func handle(message: Message.Server) async {
        Logger.debug(logLevel: .debug, scope: .network, message: "Handle web socket message", info: ["message": message])
        
        switch message {
        case .connected:
            connectResponseCompleter.resume(returning: .connected)
            await handleMessage?(message)
        case .unknown:
            Logger.debug(logLevel: .warn, scope: .network, message: "Unknown web socket message received")
        default:
            await handleMessage?(message)
        }
    }
    
    func disconnect(withError disconnectError: Error? = nil) async {
        Logger.debug(logLevel: .debug, scope: .core, error: disconnectError)

        state.mutate {
            $0.messageLoopTask?.cancel()
            $0.messageLoopTask = nil
            $0.socket?.close()
            $0.socket = nil
        }

        connectResponseCompleter.reset()

        await outgoingQueue.clear()
        await incomingQueue.clear()

        state.mutate {
            $0.connectionState = .disconnected
        }
        
        Logger.debug(logLevel: .info, scope: .network, message: "Web socket disconnected")
    }
}

extension WebSocketClient {
    func resumeIncomingQueue() async {
        await incomingQueue.resume()
    }
    
    func resumeOutgoingQueue() async {
        await outgoingQueue.resume()
    }
}

private extension WebSocketClient {
    func requireWebSocket() async throws -> WebSocket {
        guard let result = state.socket else {
            Logger.debug(logLevel: .debug, scope: .network, message: "WebSocket is nil")
            throw UserKitError.invalidState
        }

        return result
    }
}

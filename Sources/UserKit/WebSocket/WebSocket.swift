//
//  NWWebSocket.swift
//  UserKit
//
//  Created by Peter Nicholls on 21/3/2025.
//

import Foundation
import Network

/// A WebSocket client that manages a socket connection.
open class WebSocket: WebSocketConnection {

    // MARK: - Public properties

    /// The WebSocket connection delegate.
    public weak var delegate: WebSocketConnectionDelegate?

    /// The default `NWProtocolWebSocket.Options` for a WebSocket connection.
    ///
    /// These options specify that the connection automatically replies to Ping messages
    /// instead of delivering them to the `receiveMessage(data:context:)` method.
    public static var defaultOptions: NWProtocolWebSocket.Options {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true

        return options
    }

    private let errorWhileWaitingLimit = 20

    // MARK: - Private properties

    private var connection: NWConnection?
    private var endpoint: NWEndpoint?
    private var parameters: NWParameters?
    private let connectionQueue: DispatchQueue
    private var pingTimer: Timer?
    private var disconnectionWorkItem: DispatchWorkItem?
    private var isMigratingConnection = false
    private var errorWhileWaitingCount = 0

    // MARK: - Initialization

    /// Creates a `NWWebSocket` instance which connects a socket `url` with some configuration `options`.
    /// - Parameters:
    ///   - options: The configuration options for the connection. The default value is `NWWebSocket.defaultOptions`.
    ///   - connectionQueue: A `DispatchQueue` on which to deliver all connection events. The default value is `.main`.
    public init(options: NWProtocolWebSocket.Options = WebSocket.defaultOptions,
                connectionQueue: DispatchQueue = .main) {
        self.connectionQueue = connectionQueue
    }

    deinit {
        connection?.intentionalDisconnection = true
        connection?.cancel()
    }

    // MARK: - WebSocketConnection conformance

    /// Connect to the WebSocket.
    open func connect(url: URL, accessToken: String) {
        guard url.scheme == "ws" || url.scheme == "wss" else {
            delegate?.webSocketDidReceiveError(connection: self, error: NWError.posix(.EINVAL))
            return
        }
        
        endpoint = .url(url)
        if url.scheme == "ws" {
            parameters = NWParameters.tcp
        } else {
            parameters = NWParameters.tls
        }
        
        guard let endpoint = endpoint, let parameters = parameters else {
            return
        }
        
        let options = WebSocket.defaultOptions
        options.setAdditionalHeaders([(name: "Authorization", value: accessToken)])
        
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        
        if connection == nil {
            connection = NWConnection(to: endpoint, using: parameters)
            connection?.stateUpdateHandler = { [weak self] state in
                self?.stateDidChange(to: state)
            }
            connection?.betterPathUpdateHandler = { [weak self] isAvailable in
                self?.betterPath(isAvailable: isAvailable)
            }
            connection?.viabilityUpdateHandler = { [weak self] isViable in
                self?.viabilityDidChange(isViable: isViable)
            }
            listen()
            connection?.start(queue: connectionQueue)
        } else if connection?.state != .ready && !isMigratingConnection {
            connection?.start(queue: connectionQueue)
        }
    }

    /// Send a UTF-8 formatted `String` over the WebSocket.
    /// - Parameter string: The `String` that will be sent.
    open func send(string: String) {
        guard let data = string.data(using: .utf8) else {
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "textContext",
                                                  metadata: [metadata])

        send(data: data, context: context)
    }

    /// Send some `Data` over the WebSocket.
    /// - Parameter data: The `Data` that will be sent.
    open func send(data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "binaryContext",
                                                  metadata: [metadata])

        send(data: data, context: context)
    }

    /// Start listening for messages over the WebSocket.
    public func listen() {
        guard let connection = connection else {
            return
        }

        connection.receiveMessage { [weak self] (data, context, _, error) in
            guard let self = self else { return }
            if let data = data, !data.isEmpty, let context = context {
                self.receiveMessage(data: data, context: context)
            }
            if let error = error {
                self.reportErrorOrDisconnection(error)
            } else {
                self.listen() // Continue listening
            }
        }
    }

    /// Ping the WebSocket periodically.
    /// - Parameter interval: The `TimeInterval` (in seconds) with which to ping the server.
    open func ping(interval: TimeInterval) {
        pingTimer = .scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else {
                return
            }

            self.ping()
        }
        pingTimer?.tolerance = 0.01
    }

    /// Ping the WebSocket once.
    open func ping() {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        metadata.setPongHandler(connectionQueue) { [weak self] error in
            guard let self = self else {
                return
            }

            if let error = error {
                self.reportErrorOrDisconnection(error)
            } else {
                self.delegate?.webSocketDidReceivePong(connection: self)
            }
        }
        let context = NWConnection.ContentContext(identifier: "pingContext",
                                                  metadata: [metadata])

        send(data: "ping".data(using: .utf8), context: context)
    }

    /// Disconnect from the WebSocket.
    /// - Parameter closeCode: The code to use when closing the WebSocket connection.
    open func disconnect(closeCode: NWProtocolWebSocket.CloseCode = .protocolCode(.normalClosure)) {
        connection?.intentionalDisconnection = true

        // Call `cancel()` directly for a `normalClosure`
        // (Otherwise send the custom closeCode as a message).
        if closeCode == .protocolCode(.normalClosure) {
            connection?.cancel()
            scheduleDisconnectionReporting(closeCode: closeCode,
                                           reason: nil)
        } else {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
            metadata.closeCode = closeCode
            let context = NWConnection.ContentContext(identifier: "closeContext",
                                                      metadata: [metadata])

            if connection?.state == .ready {
                // See implementation of `send(data:context:)` for `scheduleDisconnection(closeCode:, reason:)`
                send(data: nil, context: context)
            } else {
                scheduleDisconnectionReporting(closeCode: closeCode, reason: nil)
            }
        }
    }

    // MARK: - Private methods

    // MARK: Connection state changes

    /// The handler for managing changes to the `connection.state` via the `stateUpdateHandler` on a `NWConnection`.
    /// - Parameter state: The new `NWConnection.State`
    private func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .ready:
            isMigratingConnection = false
            delegate?.webSocketDidConnect(connection: self)
        case .waiting(let error):
            isMigratingConnection = false
            reportErrorOrDisconnection(error)
            errorWhileWaitingCount += 1
            if errorWhileWaitingCount >= errorWhileWaitingLimit {
                tearDownConnection(error: error)
                errorWhileWaitingCount = 0
            }
        case .failed(let error):
            errorWhileWaitingCount = 0
            isMigratingConnection = false
            tearDownConnection(error: error)
        case .cancelled:
            errorWhileWaitingCount = 0
            tearDownConnection(error: nil)
        default:
            break
        }
    }

    /// The handler for informing the `delegate` if there is a better network path available
    /// - Parameter isAvailable: `true` if a better network path is available.
    private func betterPath(isAvailable: Bool) {
        if isAvailable {
            migrateConnection { [weak self] result in
                guard let self = self else {
                    return
                }

                self.delegate?.webSocketDidAttemptBetterPathMigration(result: result)
            }
        }
    }

    /// The handler for informing the `delegate` if the network connection viability has changed.
    /// - Parameter isViable: `true` if the network connection is viable.
    private func viabilityDidChange(isViable: Bool) {
        delegate?.webSocketViabilityDidChange(connection: self, isViable: isViable)
    }

    /// Attempts to migrate the active `connection` to a new one.
    ///
    /// Migrating can be useful if the active `connection` detects that a better network path has become available.
    /// - Parameter completionHandler: Returns a `Result`with the new connection if the migration was successful
    /// or a `NWError` if the migration failed for some reason.
    private func migrateConnection(completionHandler: @escaping (Result<WebSocketConnection, NWError>) -> Void) {
        guard let endpoint = endpoint, let parameters = parameters else {
            return
        }
        
        guard !isMigratingConnection else { return }
        connection?.intentionalDisconnection = true
        connection?.cancel()
        isMigratingConnection = true
        connection = NWConnection(to: endpoint, using: parameters)
        connection?.stateUpdateHandler = { [weak self] state in
            self?.stateDidChange(to: state)
        }
        connection?.betterPathUpdateHandler = { [weak self] isAvailable in
            self?.betterPath(isAvailable: isAvailable)
        }
        connection?.viabilityUpdateHandler = { [weak self] isViable in
            self?.viabilityDidChange(isViable: isViable)
        }
        listen()
        connection?.start(queue: connectionQueue)
    }

    // MARK: Connection data transfer

    /// Receive a WebSocket message, and handle it according to it's metadata.
    /// - Parameters:
    ///   - data: The `Data` that was received in the message.
    ///   - context: `ContentContext` representing the received message, and its metadata.
    private func receiveMessage(data: Data, context: NWConnection.ContentContext) {
        guard let metadata = context.protocolMetadata.first as? NWProtocolWebSocket.Metadata else {
            return
        }

        switch metadata.opcode {
        case .binary:
            self.delegate?.webSocketDidReceiveMessage(connection: self,
                                                      data: data)
        case .cont:
            //
            break
        case .text:
            guard let string = String(data: data, encoding: .utf8) else {
                return
            }
            self.delegate?.webSocketDidReceiveMessage(connection: self,
                                                      string: string)
        case .close:
            scheduleDisconnectionReporting(closeCode: metadata.closeCode,
                                           reason: data)
        case .ping:
            // SEE `autoReplyPing = true` in `init()`.
            break
        case .pong:
            // SEE `ping()` FOR PONG RECEIVE LOGIC.
            break
        @unknown default:
            break
        }
    }

    /// Send some `Data` over the  active `connection`.
    /// - Parameters:
    ///   - data: Some `Data` to send (this should be formatted as binary or UTF-8 encoded text).
    ///   - context: `ContentContext` representing the message to send, and its metadata.
    private func send(data: Data?, context: NWConnection.ContentContext) {
        connection?.send(content: data,
                         contentContext: context,
                         isComplete: true,
                         completion: .contentProcessed({ [weak self] error in
            guard let self = self else {
                return
            }

            // If a connection closure was sent, inform delegate on completion
            if let socketMetadata = context.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
               socketMetadata.opcode == .close {
                self.scheduleDisconnectionReporting(closeCode: socketMetadata.closeCode,
                                                    reason: data)
            }

            if let error = error {
                self.reportErrorOrDisconnection(error)
            }
        }))
    }

    // MARK: Connection cleanup

    /// Schedules the reporting of a WebSocket disconnection.
    ///
    /// The disconnection will be actually reported once the underlying `NWConnection` has been fully torn down.
    /// - Parameters:
    ///   - closeCode: A `NWProtocolWebSocket.CloseCode` describing how the connection closed.
    ///   - reason: Optional extra information explaining the disconnection. (Formatted as UTF-8 encoded `Data`).
    private func scheduleDisconnectionReporting(closeCode: NWProtocolWebSocket.CloseCode,
                                                reason: Data?) {
        // Cancel any existing `disconnectionWorkItem` that was set first
        disconnectionWorkItem?.cancel()

        disconnectionWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.delegate?.webSocketDidDisconnect(connection: self,
                                                  closeCode: closeCode,
                                                  reason: reason)
        }
    }

    /// Tear down the `connection`.
    ///
    /// This method should only be called in response to a `connection` which has entered either
    /// a `cancelled` or `failed` state within the `stateUpdateHandler` closure.
    /// - Parameter error: error description
    private func tearDownConnection(error: NWError?) {
        if let error = error, shouldReportNWError(error) {
            delegate?.webSocketDidReceiveError(connection: self, error: error)
        }
        pingTimer?.invalidate()
        connection?.cancel()
        connection = nil

        if let disconnectionWorkItem = disconnectionWorkItem {
            connectionQueue.async(execute: disconnectionWorkItem)
        }
    }

    /// Reports the `error` to the `delegate` (if appropriate) and if it represents an unexpected
    /// disconnection event, the disconnection will also be reported.
    /// - Parameter error: The `NWError` to inspect.
    private func reportErrorOrDisconnection(_ error: NWError) {
        if shouldReportNWError(error) {
            delegate?.webSocketDidReceiveError(connection: self, error: error)
        }

        if isDisconnectionNWError(error) {
            let reasonData = "The websocket disconnected unexpectedly".data(using: .utf8)
            scheduleDisconnectionReporting(closeCode: .protocolCode(.goingAway),
                                           reason: reasonData)
        }
    }

    /// Determine if a Network error should be reported.
    ///
    /// POSIX errors of either `ENOTCONN` ("Socket is not connected") or
    /// `ECANCELED` ("Operation canceled") should not be reported if the disconnection was intentional.
    /// All other errors should be reported.
    /// - Parameter error: The `NWError` to inspect.
    /// - Returns: `true` if the error should be reported.
    private func shouldReportNWError(_ error: NWError) -> Bool {
        if case let .posix(code) = error,
           code == .ENOTCONN || code == .ECANCELED,
           (connection?.intentionalDisconnection ?? false) {
            return false
        } else {
            return true
        }
    }

    /// Determine if a Network error represents an unexpected disconnection event.
    /// - Parameter error: The `NWError` to inspect.
    /// - Returns: `true` if the error represents an unexpected disconnection event.
    private func isDisconnectionNWError(_ error: NWError) -> Bool {
        if case let .posix(code) = error,
           code == .ETIMEDOUT
            || code == .ENOTCONN
            || code == .ECANCELED
            || code == .ENETDOWN
            || code == .ECONNABORTED {
            return true
        } else {
            return false
        }
    }
}

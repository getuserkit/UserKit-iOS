//
//  Message.swift
//  UserKit
//
//  Created by Peter Nicholls on 29/7/2025.
//

import Foundation

extension WebSocketClient {
    enum Message {
        struct Client: Encodable {
            struct Track: Encodable {
                let id: String
                let type: String
                let state: String
            }
            
            enum MessageType: String, Encodable {
                case accept = "call.participant.accept"
                case end = "call.participant.end"
                case updateTrack = "call.participant.track.update"
                case updateTracks = "call.participant.tracks.update"
                case updateParticipant = "call.participant.update"
            }

            enum Payload: Encodable {
                case end(End)
                case updateTrack(UpdateTrack)
                case updateTracks(UpdateTracks)
                case updateParticipant(UpdateParticipant)

                struct End: Encodable {
                    let uuid: UUID
                }
                
                struct UpdateTrack: Encodable {
                    let transceiverSessionId: String
                    let track: Track
                }
                
                struct UpdateTracks: Encodable {
                    let transceiverSessionId: String
                    let tracks: [Track]
                }
                
                struct UpdateParticipant: Encodable {
                    let appState: String
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .end(let end):
                        try container.encode(end)
                    case .updateTrack(let payload):
                        try container.encode(payload)
                    case .updateTracks(let payload):
                        try container.encode(payload)
                    case .updateParticipant(let payload):
                        try container.encode(payload)
                    }
                }
            }

            let type: MessageType
            let data: Payload?

            func toJSON() throws -> String {
                let data = try JSONEncoder().encode(self)
                guard let jsonString = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "EncodingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON string"])
                }
                return jsonString
            }
            
            func enqueue() -> Bool {
                switch type {
                case .accept:
                    return false
                case .end:
                    return false
                default:
                    return true
                }
            }
        }

        enum Server: Decodable {
            struct Call: Decodable, Equatable {
                struct Participant: Decodable, Equatable {
                    enum State: String, UnknownCaseDecodable {
                        case none
                        case initialized
                        case declined
                        case joined
                        case unknown
                    }
                    
                    enum AppState: String, UnknownCaseDecodable {
                        case foreground
                        case background
                        case unknown
                    }
                    
                    enum Role: String, UnknownCaseDecodable {
                        case host
                        case user
                        case unknown
                    }
                    
                    struct Track: Decodable, Equatable {
                        enum State: String, UnknownCaseDecodable {
                            case active, requested, inactive, unknown
                        }
                        
                        enum TrackType: String, UnknownCaseDecodable {
                            case audio, video, screenShare, unknown
                        }
                        
                        let state: State
                        let id: String
                        let type: TrackType
                    }

                    let id: String
                    let firstName: String?
                    let lastName: String?
                    let state: State
                    let appState: AppState
                    let role: Role
                    let tracks: [Track]
                    let transceiverSessionId: String?
                    
                    private enum CodingKeys: String, CodingKey {
                        case id, firstName, lastName, state, appState, role, tracks, transceiverSessionId
                    }
                    
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        id = try container.decode(String.self, forKey: .id)
                        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
                        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
                        state = try container.decode(State.self, forKey: .state)
                        appState = try container.decode(AppState.self, forKey: .appState)
                        role = try container.decode(Role.self, forKey: .role)
                        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
                        transceiverSessionId = try container.decodeIfPresent(String.self, forKey: .transceiverSessionId)
                    }
                }
                struct TouchIndicator: Decodable, Equatable {
                    enum State: String, UnknownCaseDecodable {
                        case active, inactive, unknown
                    }
                    
                    let state: State
                }
                let uuid: String
                let participants: [Participant]
                let touchIndicator: TouchIndicator
            }

            struct Ended: Decodable {
                let uuid: UUID
            }
            
            case callUpdated(Call?)
            case connected
            case ended(Ended)
            case unknown
            
            enum CodingKeys: CodingKey {
                case data
                case type
            }

            enum CodingError: Error {
                case missingType(Swift.DecodingError.Context)
                case unrecognizedType(Swift.DecodingError.Context)
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                guard let type = try container.decodeIfPresent(String.self, forKey: .type) else {
                    let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unrecognized type")
                    throw CodingError.unrecognizedType(context)
                }
                
                switch type {
                case "connected":
                    self = .connected
                case "call.updated":
                    let call = try container.decodeIfPresent(Call.self, forKey: .data)
                    self = .callUpdated(call)
                case "call.ended":
                    let ended = try container.decode(Ended.self, forKey: .data)
                    self = .ended(ended)
                default:
                    self = .unknown
                }
            }
            
            static func from(data: Data) throws -> Server {
                return try JSONDecoder().decode(Server.self, from: data)
            }
            
            func enqueue() -> Bool {
                switch self {
                case .connected:
                    return false
                case .ended:
                    return false
                default:
                    return true
                }
            }
        }
    }
}

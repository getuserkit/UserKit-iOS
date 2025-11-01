//
//  Host.swift
//  UserKit
//
//  Created by Peter Nicholls on 10/8/2025.
//

import WebRTC

class Host: Participant, @unchecked Sendable {
        
    // MARK: - Functions

    func set(tracks: [WebSocketClient.Message.Server.Call.Participant.Track]) async throws {
        for track in tracks {
            let remoteTrackPublication: RemoteTrackPublication
            if let existingRemoteTrackPublication = state.trackPublications[track.id] as? RemoteTrackPublication {
                remoteTrackPublication = existingRemoteTrackPublication
            } else {
                let createdRemoteTrackPublication = RemoteTrackPublication(
                    id: track.id,
                    name: track.id,
                    kind: .init(type: track.type),
                    source: .init(type: track.type),
                    participant: self
                )

                createdRemoteTrackPublication.muteDidChange = { [weak self, weak createdRemoteTrackPublication] in
                    guard let self, let createdRemoteTrackPublication else { return }
                    Task { await self.muteDidChange?(createdRemoteTrackPublication) }
                }

                add(publication: createdRemoteTrackPublication)
                remoteTrackPublication = createdRemoteTrackPublication
            }

            remoteTrackPublication.set(isMuted: track.state != .active)
        }
        
        let publications: [RemoteTrackPublication] =
            trackPublications.values
                .compactMap { $0 as? RemoteTrackPublication }
                .filter { $0.subscriptionState == .unsubscribed && !$0.isMuted }
        try await pull(trackPublications: publications)
    }
    
    func pull(trackPublications: [RemoteTrackPublication]) async throws {
        guard let call = call, let accessToken = call.accessToken, let transport = call.transport, let sessionId = call.sessionId else {
            throw UserKitError.invalidState
        }
        
        if trackPublications.isEmpty { return }
                                                                        
        var tracks: [APIClient.PullTracksRequest.Track] = []
        for publication in trackPublications {
            try await publication.set(subscriptionState: .subscribed)
            
            let parts = publication.id.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw UserKitError.invalidState
            }

            let participantSessionId = parts[0]
            let trackId = parts[1]
                        
            tracks.append(
                APIClient.PullTracksRequest.Track(
                    location: "remote",
                    trackName: trackId,
                    sessionId: participantSessionId
                )
            )
        }
        
        let response = try await call.apiClient.request(
            accessToken: accessToken,
            endpoint: .pullTracks(sessionId, .init(tracks: tracks)),
            as: APIClient.PullTracksResponse.self
        )
        
        for responseTrack in response.tracks {
            if let publication = trackPublications.first(where: {
                let parts = $0.id.split(separator: "/", maxSplits: 1).map(String.init)
                return parts.count == 2 && parts[1] == responseTrack.trackName && parts[0] == responseTrack.sessionId
            }) {
                publication.state.mutate { $0.mid = responseTrack.mid }
            }
        }
        
        guard let sessionDescription = response.sessionDescription else {
            throw UserKitError.invalidState
        }
        
        try await transport.set(remoteDescription: .init(type: RTCSessionDescription.type(for: sessionDescription.type), sdp: sessionDescription.sdp))
        let answer = try await transport.createAnswer()
        try await transport.set(localDescription: answer)
        
        let renegotiate = try await call.apiClient.request(
            accessToken: accessToken,
            endpoint: .renegotiate(sessionId, .init(
                sessionDescription: .init(sdp: answer.sdp, type: "answer")
            )),
            as: APIClient.RenegotiateResponse.self
        )
    }
}

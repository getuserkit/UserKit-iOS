//
//  ParticipantView.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit
import UIKit
import WebRTC

class ParticipantView {

    let videoDisplayView: SampleBufferVideoCallView
    let avatarView: AvatarView
    let muteImageView: UIImageView
    var frameRenderer: PictureInPictureFrameRender?

    private weak var participant: Participant?

    init() {
        self.videoDisplayView = SampleBufferVideoCallView()
        videoDisplayView.translatesAutoresizingMaskIntoConstraints = false

        self.avatarView = AvatarView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        self.muteImageView = UIImageView(frame: .zero)
        muteImageView.image = UIImage(systemName: "microphone.slash")
        muteImageView.translatesAutoresizingMaskIntoConstraints = false
        muteImageView.tintColor = .white
    }

    func configure(participant: Participant) {
        self.participant = participant

        avatarView.set(backgroundColor: participant.avatarColor)
        avatarView.set(initials: participant.label)
        avatarView.isHidden = participant.isCameraEnabled
        muteImageView.isHidden = participant.isMicrophoneEnabled
    }

    func setVideoTrack(_ track: RTCVideoTrack?, oldTrack: RTCVideoTrack?) {
        if let track = track {
            let renderer = PictureInPictureFrameRender(
                displayLayer: videoDisplayView.sampleBufferDisplayLayer,
                flipFrame: true
            )

            frameRenderer?.clean()
            frameRenderer = renderer
            track.add(renderer)
        } else {
            if let renderer = frameRenderer {
                renderer.clean()
                if let oldTrack = oldTrack {
                    oldTrack.remove(renderer)
                }
            }
        }
    }

    func setupConstraints(in parentView: UIView, topAnchor: NSLayoutYAxisAnchor, bottomAnchor: NSLayoutYAxisAnchor) {
        parentView.addSubview(videoDisplayView)
        parentView.addSubview(avatarView)
        parentView.addSubview(muteImageView)

        NSLayoutConstraint.activate([
            videoDisplayView.topAnchor.constraint(equalTo: topAnchor),
            videoDisplayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            videoDisplayView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            videoDisplayView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            muteImageView.widthAnchor.constraint(equalToConstant: 22),
            muteImageView.heightAnchor.constraint(equalToConstant: 22),
            muteImageView.leadingAnchor.constraint(equalTo: videoDisplayView.leadingAnchor, constant: 8),
            muteImageView.bottomAnchor.constraint(equalTo: videoDisplayView.bottomAnchor, constant: -8)
        ])
    }

    func clean() {
        frameRenderer?.clean()
        frameRenderer = nil
    }
}

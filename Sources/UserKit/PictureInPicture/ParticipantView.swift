//
//  ParticipantView.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit
import UIKit
import WebRTC

class ParticipantView: UIView {

    let videoDisplayView: SampleBufferVideoCallView
    let avatarView: AvatarView
    let muteImageView: UIImageView
    var frameRenderer: PictureInPictureFrameRender?

    private(set) var participantId: String?

    init() {
        videoDisplayView = SampleBufferVideoCallView()
        videoDisplayView.translatesAutoresizingMaskIntoConstraints = false

        avatarView = AvatarView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        muteImageView = UIImageView(frame: .zero)
        muteImageView.image = UIImage(systemName: "microphone.slash")
        muteImageView.translatesAutoresizingMaskIntoConstraints = false
        muteImageView.tintColor = .white

        super.init(frame: .zero)

        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        addSubview(videoDisplayView)
        addSubview(avatarView)
        addSubview(muteImageView)

        NSLayoutConstraint.activate([
            videoDisplayView.topAnchor.constraint(equalTo: topAnchor),
            videoDisplayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            videoDisplayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoDisplayView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: topAnchor),
            avatarView.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            muteImageView.widthAnchor.constraint(equalToConstant: 22),
            muteImageView.heightAnchor.constraint(equalToConstant: 22),
            muteImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            muteImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    func configure(participant: Participant, isLocalUser: Bool) {
        self.participantId = participant.id

        if isLocalUser {
            videoDisplayView.backgroundColor = .black
            avatarView.set(backgroundColor: UIColor(red: 0.89, green: 0.47, blue: 0.33, alpha: 1.0))
            avatarView.set(initials: "You")
        } else {
            avatarView.set(backgroundColor: participant.avatarColor)
            avatarView.set(initials: participant.initials)
        }

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
            if let oldTrack = oldTrack {
                oldTrack.remove(frameRenderer!)
            }

            frameRenderer = renderer
            track.add(renderer)
        } else {
            if let renderer = frameRenderer, let oldTrack = oldTrack {
                renderer.clean()
                oldTrack.remove(renderer)
            }
            frameRenderer = nil
        }
    }

    func updateMuteState(isMuted: Bool) {
        muteImageView.isHidden = !isMuted
    }

    func updateCameraState(isEnabled: Bool) {
        avatarView.isHidden = isEnabled
    }

    func clean() {
        frameRenderer?.clean()
        frameRenderer = nil
    }
}

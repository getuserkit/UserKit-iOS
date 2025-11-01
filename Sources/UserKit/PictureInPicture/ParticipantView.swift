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
    let speakingImageView: UIImageView
    var frameRenderer: PictureInPictureFrameRender?

    private weak var participant: Participant?
    private let audioLevelThresholdInitial: Float = 0.1
    private let audioLevelThresholdSpeaking: Float = 0.02
    private var isMuted: Bool = true
    private var isSpeaking: Bool = false
    private var hideIndicatorTask: Task<Void, Never>?

    init() {
        self.videoDisplayView = SampleBufferVideoCallView()
        videoDisplayView.translatesAutoresizingMaskIntoConstraints = false

        self.avatarView = AvatarView()
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        self.muteImageView = UIImageView(frame: .zero)
        muteImageView.image = UIImage(systemName: "microphone.slash")
        muteImageView.translatesAutoresizingMaskIntoConstraints = false
        muteImageView.tintColor = .white
        muteImageView.alpha = 0.0

        self.speakingImageView = UIImageView(frame: .zero)
        speakingImageView.image = UIImage(systemName: "microphone.fill")
        speakingImageView.translatesAutoresizingMaskIntoConstraints = false
        speakingImageView.tintColor = .white
        speakingImageView.alpha = 0.0
    }

    func configure(participant: Participant) {
        self.participant = participant

        avatarView.set(backgroundColor: participant.avatarColor)
        avatarView.set(initials: participant.label)
        avatarView.isHidden = participant.isCameraEnabled

        self.isMuted = !participant.isMicrophoneEnabled
        muteImageView.alpha = participant.isMicrophoneEnabled ? 0.0 : 1.0
    }

    func updateMuteState(isMuted: Bool) {
        self.isMuted = isMuted

        UIView.animate(withDuration: 0.2) {
            self.muteImageView.alpha = isMuted ? 1.0 : 0.0
            if isMuted {
                self.speakingImageView.alpha = 0.0
            }
        }
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
        parentView.addSubview(speakingImageView)

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
            muteImageView.widthAnchor.constraint(equalToConstant: 16),
            muteImageView.heightAnchor.constraint(equalToConstant: 16),
            muteImageView.leadingAnchor.constraint(equalTo: videoDisplayView.leadingAnchor, constant: 8),
            muteImageView.bottomAnchor.constraint(equalTo: videoDisplayView.bottomAnchor, constant: -8)
        ])

        NSLayoutConstraint.activate([
            speakingImageView.widthAnchor.constraint(equalToConstant: 16),
            speakingImageView.heightAnchor.constraint(equalToConstant: 16),
            speakingImageView.leadingAnchor.constraint(equalTo: videoDisplayView.leadingAnchor, constant: 8),
            speakingImageView.bottomAnchor.constraint(equalTo: videoDisplayView.bottomAnchor, constant: -8)
        ])
    }

    func updateAudioLevel(_ level: Float) {
        guard !isMuted else {
            hideIndicatorTask?.cancel()
            hideIndicatorTask = nil
            isSpeaking = false
            UIView.animate(withDuration: 0.2) {
                self.speakingImageView.alpha = 0.0
            }
            return
        }

        let threshold = isSpeaking ? audioLevelThresholdSpeaking : audioLevelThresholdInitial
        let audioLevelAboveThreshold = level > threshold

        if audioLevelAboveThreshold {
            hideIndicatorTask?.cancel()
            hideIndicatorTask = nil
            isSpeaking = true

            UIView.animate(withDuration: 0.2) {
                self.speakingImageView.alpha = 1.0
            }
        } else if hideIndicatorTask == nil {
            hideIndicatorTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self?.isSpeaking = false
                    UIView.animate(withDuration: 0.2) {
                        self?.speakingImageView.alpha = 0.0
                    }
                    self?.hideIndicatorTask = nil
                }
            }
        }
    }

    func clean() {
        hideIndicatorTask?.cancel()
        hideIndicatorTask = nil
        frameRenderer?.clean()
        frameRenderer = nil
    }
}

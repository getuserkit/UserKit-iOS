//
//  PictureInPictureViewController.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import AVKit
import SwiftUI
import WebRTC

protocol PictureInPictureViewControllerDelegate: AnyObject {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool
}

final class PictureInPictureViewController: UIViewController {
    
    // MARK: - Properties
        
    weak var delegate: PictureInPictureViewControllerDelegate?
    
    lazy var pictureInPictureController: AVPictureInPictureController = {
        let pictureInPictureController = AVPictureInPictureController(contentSource: pictureInPictureControllerContentSource)
        return pictureInPictureController
    }()
        
    private lazy var pictureInPictureVideoCallViewController: PictureInPictureVideoCallViewController = {
        let pictureInPictureVideoCallViewController = PictureInPictureVideoCallViewController()
        return pictureInPictureVideoCallViewController
    }()

    private lazy var pictureInPictureControllerContentSource: AVPictureInPictureController.ContentSource = {
        let pictureInPictureControllerContentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: view,
            contentViewController: pictureInPictureVideoCallViewController
        )
        return pictureInPictureControllerContentSource
    }()
    
    private var videoTrack: RTCVideoTrack? {
        didSet {
            oldValue?.remove(pictureInPictureVideoCallViewController.videoView)
            
            if let videoTrack = videoTrack {
                videoTrack.add(pictureInPictureVideoCallViewController.videoView)
            }
        }
    }
                
    // MARK: - Functions
            
    override func viewDidLoad() {
        super.viewDidLoad()
                        
        view.backgroundColor = .clear
        
        // Picture in picture needs to be called here,
        // something about being a lazy var causes it not to start
        pictureInPictureController.delegate = self
        pictureInPictureController.canStartPictureInPictureAutomaticallyFromInline = false
    }
    
    func set(avatar url: URL?) {
        guard let url = url else {
            pictureInPictureVideoCallViewController.iconImageView.image = nil
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        pictureInPictureVideoCallViewController.iconImageView.image = image
                    }
                }
            } catch {
                print("Failed to load placeholder image: \(error)")
            }
        }
    }
        
    func set(track: RTCVideoTrack?) {
        self.videoTrack = track
    }
}

extension PictureInPictureViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        Logger.debug(
            logLevel: .error,
            scope: .core,
            message: "Failed to start picture in picture",
            error: error
        )
    }
     
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController) async -> Bool {
        guard let delegate = delegate else {
            return true
        }
    
        return await delegate.pictureInPictureController(pictureInPictureController)
    }
}

class PictureInPictureVideoCallViewController: AVPictureInPictureVideoCallViewController {
    
    // MARK: - Properties
    
    lazy var videoView: RTCMTLVideoView = {
        let videoView = RTCMTLVideoView()
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.transform = CGAffineTransform(scaleX: -1, y: 1)
        videoView.backgroundColor = .systemBackground
        videoView.layer.cornerRadius = 12
        videoView.layer.masksToBounds = true
        videoView.isHidden = true
        return videoView
    }()
    
    lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.layer.cornerRadius = 12
        imageView.layer.masksToBounds = true
        return imageView
    }()
      
    // MARK: - Functions
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        
        view.addSubview(iconImageView)
        view.addSubview(videoView)
        
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: view.topAnchor),
            iconImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            iconImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            iconImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}

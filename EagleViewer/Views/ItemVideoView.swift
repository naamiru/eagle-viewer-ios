//
//  ItemVideoView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import AVFoundation
import AVKit
import OSLog
import SwiftUI

struct ItemVideoView: UIViewControllerRepresentable {
    static func isVideo(item: Item) -> Bool {
        item.duration > 0
    }

    let item: Item
    let dismiss: () -> Void

    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> LauncherViewController {
        let controller = LauncherViewController()
        controller.coordinator = context.coordinator
        controller.videoURL = videoURL()
        return controller
    }

    func updateUIViewController(_ uiViewController: LauncherViewController, context: Context) {
        context.coordinator.dismiss = dismiss
        let url = videoURL()
        if uiViewController.videoURL != url {
            uiViewController.videoURL = url
            uiViewController.resetPresentationIfNeeded()
        }
    }

    private func videoURL() -> URL? {
        guard let baseURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return baseURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        var dismiss: (() -> Void)?

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
        }

        private func triggerDismiss() {
            guard let dismiss else { return }
            self.dismiss = nil
            DispatchQueue.main.async {
                dismiss()
            }
        }

        func dismissIfNeeded() {
            triggerDismiss()
        }

        func playerViewControllerWillDismiss(_ playerViewController: AVPlayerViewController) {
            triggerDismiss()
        }

        func playerViewControllerDidDismiss(_ playerViewController: AVPlayerViewController) {
            triggerDismiss()
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            triggerDismiss()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            triggerDismiss()
        }
    }

    final class LauncherViewController: UIViewController {
        var videoURL: URL?
        var coordinator: Coordinator?

        private var hasPresentedPlayer = false
        private var player: AVQueuePlayer?
        private var playerLooper: AVPlayerLooper?
        private var hasConfiguredAudioSession = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if hasPresentedPlayer, presentedViewController == nil {
                hasPresentedPlayer = false
                deactivateAudioSessionIfNeeded()
                player?.pause()
                player = nil
                playerLooper = nil
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator?.dismissIfNeeded()
                }
            } else {
                presentPlayerIfNeeded()
            }
        }

        func resetPresentationIfNeeded() {
            hasPresentedPlayer = false
            if isViewLoaded, view.window != nil {
                presentPlayerIfNeeded()
            }
        }

        private func presentPlayerIfNeeded() {
            guard !hasPresentedPlayer else { return }
            hasPresentedPlayer = true

            guard let videoURL else {
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator?.dismissIfNeeded()
                }
                return
            }

            configureAudioSessionIfNeeded()

            let asset = AVURLAsset(url: videoURL)
            let playerItem = AVPlayerItem(asset: asset)
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

            player = queuePlayer
            playerLooper = looper

            let playerController = AVPlayerViewController()
            playerController.player = queuePlayer
            playerController.delegate = coordinator
            playerController.entersFullScreenWhenPlaybackBegins = true
            playerController.allowsPictureInPicturePlayback = true
            playerController.modalPresentationStyle = .fullScreen

            present(playerController, animated: true) { [weak self, weak playerController] in
                playerController?.presentationController?.delegate = self?.coordinator
                queuePlayer.play()
            }
        }

        private func configureAudioSessionIfNeeded() {
            guard !hasConfiguredAudioSession else { return }

            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try session.setActive(true, options: [])
                hasConfiguredAudioSession = true
            } catch {
                Logger.app.warning("Failed to configure audio session for video playback: \(error.localizedDescription)")
            }
        }

        private func deactivateAudioSessionIfNeeded() {
            guard hasConfiguredAudioSession else { return }
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                Logger.app.warning("Failed to deactivate audio session after video playback: \(error.localizedDescription)")
            }
            hasConfiguredAudioSession = false
        }
    }
}

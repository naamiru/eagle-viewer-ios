//
//  ItemThumbnailView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import AVFoundation
import AVKit
import SwiftUI

struct ItemVideoView: View {
    static func isVideo(item: Item) -> Bool {
        return item.duration != 0
    }

    let item: Item
    @Binding var isNoUI: Bool

    @State private var player: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?
    @State private var loadTaskID: UUID?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserverToken: Any?

    @EnvironmentObject private var imageViewerManager: ImageViewerManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager

    private var videoURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(isNoUI ? Color.black : Color.white)
                .ignoresSafeArea()

            ProgressView()
                .progressViewStyle(.circular)
                .tint(isNoUI ? .white : .gray)
        }
    }

    private var sliderRange: ClosedRange<Double> {
        0 ... max(duration, 0.001)
    }

    private var seekBar: some View {
        Slider(
            value: Binding(
                get: { currentTime },
                set: { newValue in
                    currentTime = min(max(newValue, sliderRange.lowerBound), sliderRange.upperBound)
                }
            ),
            in: sliderRange,
            onEditingChanged: handleSliderEditingChanged
        )
        .tint(.accentColor)
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }

    var body: some View {
        ZStack {
            (isNoUI ? Color.black : Color.white)
                .ignoresSafeArea()

            Group {
                if let player {
                    VideoPlayer(player: player)
                        .allowsHitTesting(false)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    placeholder
                }
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNoUI.toggle()
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if !isNoUI, duration > 0 {
                seekBar
            }
        }
        .onAppear {
            prepareVideoPlayer()

            if let player, timeObserverToken == nil {
                installTimeObserver(for: player)
            }
        }
        .onChange(of: videoURL) {
            prepareVideoPlayer(forceReload: true)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            loadTaskID = nil
            isLoading = false
            removeTimeObserver(from: player)
            player?.pause()
        }
    }

    private func prepareVideoPlayer(forceReload: Bool = false) {
        if forceReload {
            loadTask?.cancel()
            loadTask = nil
            loadTaskID = nil
            removeTimeObserver(from: player)
            player?.pause()
            player = nil
            playerLooper = nil
            currentTime = 0
            duration = 0
        } else if player != nil || loadTask != nil {
            return
        }

        guard let url = videoURL else {
            isLoading = false
            return
        }

        let needsDownload = needsMaterialization(for: url)
        isLoading = needsDownload

        let taskID = UUID()
        loadTaskID = taskID

        let task = Task {
            do {
                if needsDownload {
                    try await CloudFile.ensureMaterialized(at: url)

                    if Task.isCancelled {
                        await MainActor.run {
                            if loadTaskID == taskID {
                                isLoading = false
                                loadTask = nil
                                loadTaskID = nil
                            }
                        }
                        return
                    }
                }

                let asset = AVURLAsset(url: url)
                let assetDuration = try await asset.load(.duration)
                let playerItem = AVPlayerItem(asset: asset)

                await MainActor.run {
                    guard loadTaskID == taskID else { return }
                    removeTimeObserver(from: player)
                    let queuePlayer = AVQueuePlayer(playerItem: playerItem)
                    player = queuePlayer
                    playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
                    duration = assetDuration.seconds.isFinite ? max(assetDuration.seconds, 0) : 0
                    currentTime = 0
                    installTimeObserver(for: queuePlayer)
                    isLoading = false
                    loadTask = nil
                    loadTaskID = nil
                }
            } catch {
                await MainActor.run {
                    if loadTaskID == taskID {
                        isLoading = false
                        loadTask = nil
                        loadTaskID = nil
                    }
                }
            }
        }

        loadTask = task
    }

    private func needsMaterialization(for url: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: url.path) {
            return true
        }

        let (isUbiq, isCurrent) = (try? CloudFile.ubiquitousQuickState(url)) ?? (false, false)
        return isUbiq && !isCurrent
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        guard let player else { return }

        isScrubbing = isEditing

        if isEditing {
            player.pause()
        } else {
            seek(to: currentTime)
            player.play()
        }
    }

    private func seek(to seconds: Double) {
        guard let player else { return }

        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func installTimeObserver(for player: AVQueuePlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing else { return }

            let seconds = time.seconds
            if seconds.isFinite {
                currentTime = min(max(seconds, sliderRange.lowerBound), sliderRange.upperBound)
            }
        }
    }

    private func removeTimeObserver(from player: AVQueuePlayer?) {
        guard let player, let token = timeObserverToken else { return }
        player.removeTimeObserver(token)
        timeObserverToken = nil
    }
}

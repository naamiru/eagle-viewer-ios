//
//  ItemThumbnailView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

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

    @EnvironmentObject private var imageViewerManager: ImageViewerManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager

    private var videoURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
                .ignoresSafeArea()

            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
        }
    }

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
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
        .onAppear {
            prepareVideoPlayer()
        }
        .onChange(of: videoURL) {
            prepareVideoPlayer(forceReload: true)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            loadTaskID = nil
            isLoading = false
            player?.pause()
        }
    }

    private func prepareVideoPlayer(forceReload: Bool = false) {
        if forceReload {
            loadTask?.cancel()
            loadTask = nil
            loadTaskID = nil
            player?.pause()
            player = nil
            playerLooper = nil
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
                let playerItem = AVPlayerItem(asset: asset)

                await MainActor.run {
                    guard loadTaskID == taskID else { return }
                    let queuePlayer = AVQueuePlayer(playerItem: playerItem)
                    player = queuePlayer
                    playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
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
}

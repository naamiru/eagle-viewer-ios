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
    let dismiss: () -> Void
    
    @State private var player: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    
    @State private var showCloseButton = true
    @State private var hideButtonTask: Task<Void, Never>?
    
    @EnvironmentObject private var imageViewerManager: ImageViewerManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    
    private var videoURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }
        
        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }
    
    private var placeholder: some View {
        Rectangle().fill(Color.gray.opacity(0.3))
            .aspectRatio(CGSize(width: item.width, height: item.height), contentMode: .fit)
    }
    
    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player) {
                    if showCloseButton {
                        VStack {
                            HStack {
                                Button(action: {
                                    dismiss()
                                }) {
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.white)
                                }

                                Spacer()
                            }
                            .padding()

                            Spacer()
                        }
                        .transition(.opacity) // not working
                    }
                }
                .ignoresSafeArea()
                .simultaneousGesture(tapShowButtonGesture())
                .simultaneousGesture(dragCloseGesture())
                .onAppear {
                    player.play()
                    scheduleButtonHide()
                }
                .onDisappear {
                    player.pause()
                }
            } else {
                placeholder
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if let videoURL {
                let asset = AVURLAsset(url: videoURL)
                let item = AVPlayerItem(asset: asset)
                player = AVQueuePlayer(playerItem: item)
                playerLooper = AVPlayerLooper(player: player!, templateItem: item)
            }
        }
    }
    
    private func dragCloseGesture() -> some Gesture {
        DragGesture()
            .onEnded { value in
                let w = abs(value.translation.width), h = value.translation.height
                if h > 10, w < 20, w / h < 0.2 {
                    dismiss()
                }
            }
    }
    
    private func tapShowButtonGesture() -> some Gesture {
        TapGesture()
            .onEnded { _ in
                hideButtonTask?.cancel()

                // show close button after 0.5sec
                hideButtonTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                                
                    if !Task.isCancelled {
                        showCloseButton = true
                        scheduleButtonHide()
                    }
                }
            }
    }
    
    private func scheduleButtonHide() {
        hideButtonTask?.cancel()

        // hide close button after 5sec
        hideButtonTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
                
            if !Task.isCancelled {
                withAnimation {
                    showCloseButton = false
                }
            }
        }
    }
}

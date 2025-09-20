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
    
    @State private var player: AVPlayer?
    
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
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.white)
                            }
                            .padding()
                        }
                        Spacer()
                    }
                }
                .ignoresSafeArea()
                .simultaneousGesture(dragCloseGesture())
                .onAppear {
                    player.play()
                }
            } else {
                placeholder
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if let videoURL {
                player = AVPlayer(url: videoURL)
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
}

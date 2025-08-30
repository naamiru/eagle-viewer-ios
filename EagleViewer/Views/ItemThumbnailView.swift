//
//  ItemThumbnailView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import NukeUI
import SwiftUI

struct ThumbnailView: View {
    let url: URL
    @Binding private var isPlaceholder: Bool
    
    init(url: URL, isPlaceholder: Binding<Bool> = .constant(false)) {
        self.url = url
        _isPlaceholder = isPlaceholder
    }
    
    @ViewBuilder
    private func imageView(state: LazyImageState) -> some View {
        if let image = state.image {
            image
                .resizable()
                .scaledToFill()
        } else if state.error != nil {
            // error
            ThumbnailError()
        } else {
            // loading
            ThumbnailLoading()
        }
    }
    
    private func isSuccessState(_ state: LazyImageState) -> Bool {
        state.image != nil
    }
    
    var body: some View {
        LazyImage(url: url) { state in
            imageView(state: state)
                .onChange(of: isSuccessState(state), initial: true) { _, isSuccess in
                    isPlaceholder = !isSuccess
                }
        }
    }
}

struct ThumbnailError: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
    }
}

struct ThumbnailLoading: View {
    var body: some View {
        ZStack {
            Color.gray.opacity(0.4)

            Image(systemName: "photo")
                .foregroundColor(.gray.opacity(0.2))
                .font(.system(size: 24))
        }
    }
}

struct ItemThumbnailView: View {
    let item: Item
    @Binding private var isPlaceholder: Bool
    
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    
    init(item: Item, isPlaceholder: Binding<Bool> = .constant(false)) {
        self.item = item
        _isPlaceholder = isPlaceholder
    }
    
    private var imageURL: URL? {
        guard let currentLibraryUrl = libraryFolderManager.currentLibraryURL else {
            return nil
        }
        
        return currentLibraryUrl.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
    }
    
    var body: some View {
        if let imageURL {
            ThumbnailView(url: imageURL, isPlaceholder: $isPlaceholder)
        } else {
            ThumbnailError()
                .onAppear {
                    isPlaceholder = true
                }
        }
    }
}

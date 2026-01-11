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

enum TextThumbnailStyle {
    case standard
    case detailSlider
}

struct TextThumbnailView: View {
    let style: TextThumbnailStyle
    let itemName: String
    @Binding private var isPlaceholder: Bool

    init(style: TextThumbnailStyle = .standard, itemName: String, isPlaceholder: Binding<Bool> = .constant(false)) {
        self.style = style
        self.itemName = itemName
        _isPlaceholder = isPlaceholder
    }

    var body: some View {
        ZStack {
            switch style {
            case .standard:
                Color.gray.opacity(0.4)

                VStack(spacing: 8) {
                    Image(systemName: "doc.plaintext")
                        .foregroundColor(.gray.opacity(0.9))
                        .font(.system(size: 24, weight: .regular))

                    Text(itemName)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.gray.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(height: 32, alignment: .top)
                }
                .padding(6)
                .offset(y: 6)
            case .detailSlider:
                Color.clear

                Image(systemName: "doc.plaintext")
                    .foregroundColor(.secondary.opacity(0.8))
                    .font(.system(size: 20, weight: .regular))
                    .padding(6)
                    .background(Color.white)
            }
        }
        .onAppear {
            isPlaceholder = true
        }
    }
}

struct ItemThumbnailView: View {
    let item: Item
    let textThumbnailStyle: TextThumbnailStyle
    @Binding private var isPlaceholder: Bool
    
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    
    init(
        item: Item,
        textThumbnailStyle: TextThumbnailStyle = .standard,
        isPlaceholder: Binding<Bool> = .constant(false)
    ) {
        self.item = item
        self.textThumbnailStyle = textThumbnailStyle
        _isPlaceholder = isPlaceholder
    }
    
    private var imageURL: URL? {
        guard let currentLibraryUrl = libraryFolderManager.currentLibraryURL else {
            return nil
        }
        
        return currentLibraryUrl.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
    }
    
    var body: some View {
        if item.isTextFile {
            TextThumbnailView(
                style: textThumbnailStyle,
                itemName: item.name,
                isPlaceholder: $isPlaceholder
            )
        } else if let imageURL {
            ThumbnailView(url: imageURL, isPlaceholder: $isPlaceholder)
        } else {
            ThumbnailError()
                .onAppear {
                    isPlaceholder = true
                }
        }
    }
}

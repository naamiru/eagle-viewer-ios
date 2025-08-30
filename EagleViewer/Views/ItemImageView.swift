//
//  ItemThumbnailView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import NukeUI
import SwiftUI

struct ItemImageView: View {
    let item: Item
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    
    private var imageURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }
        
        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }
    
    private var placeholder: some View {
        Rectangle().fill(Color.gray.opacity(0.3))
            .aspectRatio(CGSize(width: item.width, height: item.height), contentMode: .fit)
    }
    
    private var loader: some View {
        Rectangle().fill(Color.clear)
            .aspectRatio(CGSize(width: item.width, height: item.height), contentMode: .fit)
    }
    
    var body: some View {
        if let imageURL {
            LazyImage(url: imageURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(CGSize(width: item.width, height: item.height), contentMode: .fit)
                } else if state.error != nil {
                    placeholder
                } else {
                    loader
                }
            }
        } else {
            placeholder
        }
    }
}

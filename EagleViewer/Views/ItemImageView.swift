//
//  ItemImageView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import NukeUI
import SwiftUI

struct ItemImageView: View {
    let item: Item
    let isSelected: Bool
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @State private var resolvedURL: URL?
    @State private var downloadAttempted = false

    private var localImageURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }
        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    private var isOneDrive: Bool {
        libraryFolderManager.oneDriveRootItemId != nil
    }

    private var placeholder: some View {
        Rectangle().fill(Color.gray.opacity(0.3))
            .aspectRatio(CGSize(width: item.width, height: item.height), contentMode: .fit)
    }

    private var loader: some View {
        Rectangle().fill(Color.clear)
            .aspectRatio(CGSize(width: item.width, height: item.height), contentMode: .fit)
    }

    @ViewBuilder
    private func imageContent(url: URL) -> some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                if item.imagePath.lowercased().hasSuffix(".gif")
                    || item.imagePath.lowercased().hasSuffix(".webp")
                {
                    AnimatedImageView(
                        url: url,
                        contentMode: .scaleAspectFit,
                        shouldAnimate: isSelected
                    )
                } else {
                    image
                        .resizable()
                        .aspectRatio(CGSize(width: item.width, height: item.height), contentMode: .fit)
                }
            } else if state.error != nil {
                placeholder
            } else {
                loader
            }
        }
    }

    var body: some View {
        if let url = resolvedURL {
            imageContent(url: url)
        } else if isOneDrive {
            // OneDrive lazy loading: show loader while downloading
            loader
                .task {
                    guard !downloadAttempted else { return }
                    downloadAttempted = true
                    await downloadOnDemand()
                }
        } else if let imageURL = localImageURL {
            imageContent(url: imageURL)
        } else {
            placeholder
        }
    }

    private func downloadOnDemand() async {
        guard let rootItemId = libraryFolderManager.oneDriveRootItemId,
              let baseURL = libraryFolderManager.currentLibraryURL
        else { return }

        let url = await OneDriveImageDownloader.shared.ensureImageExists(
            rootItemId: rootItemId,
            relativePath: item.imagePath,
            localBaseURL: baseURL
        )

        await MainActor.run {
            resolvedURL = url
        }
    }
}

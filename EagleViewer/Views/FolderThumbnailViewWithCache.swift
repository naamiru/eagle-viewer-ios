//
//  FolderThumbnailViewWithCache.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import GRDB
import SwiftUI

struct FolderThumbnailViewWithCache: View {
    enum CoverImageState {
        case loading
        case success(URL)
        case empty // folder doesn't have cover image
        case error
    }

    let folder: Folder
    @State private var coverImageState: CoverImageState = .loading

    @Environment(\.databaseContext) private var databaseContext
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @EnvironmentObject private var eventCenter: EventCenter

    var body: some View {
        Group {
            switch coverImageState {
            case .success(let url):
                CollectionURLThumbnailView(title: folder.name, url: url, showLabel: settingsManager.layout != .col6)
            case .loading:
                CollectionThumbnailView(title: folder.name, noGradation: true, showLabel: settingsManager.layout != .col6) {
                    ThumbnailLoading()
                }
            default:
                CollectionThumbnailView(title: folder.name, showLabel: settingsManager.layout != .col6)
            }
        }
        .task(id: folder.id) {
            await loadCoverItem()
        }
        .onChange(of: folder) {
            Task {
                await loadCoverItem()
            }
        }
        .onReceive(eventCenter.publisher) { event in
            if case .folderCacheInvalidated = event {
                Task {
                    await loadCoverItem()
                }
            }
        }
    }

    private func loadCoverItem() async {
        do {
            let cachedEntry = await CacheManager.shared.findFolderCoverImage(folderId: folder.folderId)
            if let cachedEntry {
                await MainActor.run {
                    coverImageState = entryToCoverImageState(cachedEntry)
                }

                // If cache is fresh, no need to reload
                if case .fresh = cachedEntry {
                    return
                }
            }

            let globalSortOption = settingsManager.globalSortOption
            let libraryURL = libraryFolderManager.currentLibraryURL

            guard let libraryURL else {
                await MainActor.run {
                    coverImageState = .error
                }
                return
            }

            let entry = try await CacheManager.shared.findOrCreateFolderCoverImage(folderId: folder.folderId) {
                if let item = try await getCoverItemFromDB(globalSortOption: globalSortOption) {
                    return .url(libraryURL.appending(path: item.thumbnailPath, directoryHint: .notDirectory))
                }
                return .empty
            }
            await MainActor.run {
                coverImageState = entryToCoverImageState(entry)
            }
        } catch {
            await MainActor.run {
                coverImageState = .error
            }
        }
    }

    private func entryToCoverImageState(_ cacheStateEntry: CacheManager.Entry<CacheManager.CoverImageState>) -> CoverImageState {
        switch cacheStateEntry {
        case .fresh(let state), .stale(let state):
            switch state {
            case .empty:
                return .empty
            case .url(let url):
                return .success(url)
            }
        }
    }

    private func getCoverItemFromDB(globalSortOption: GlobalSortOption) async throws -> Item? {
        try await databaseContext.reader.read { db in
            // First try to get direct child items
            if let item = try FolderQuery.folderItems(folder: folder, globalSortOption: globalSortOption)
                .fetchOne(db)
            {
                return item
            }

            // If no direct items, search in descendant folders
            return try FolderQuery.folderItemsWithDescendantFallback(folder: folder, globalSortOption: globalSortOption)
                .fetchOne(db)
        }
    }
}

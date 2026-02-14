//
//  FolderThumbnailViewWithCache.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import GRDB
import SwiftUI

struct FolderThumbnailViewWithCache: View {
    enum CoverImageState: Equatable {
        case loading
        case success(URL)
        case empty // folder doesn't have cover image
        case error
    }

    let folder: Folder
    @State private var coverImageState: CoverImageState = .loading
    /// For OneDrive: tracks the downloaded cover URL, triggers re-render when set.
    @State private var oneDriveResolvedURL: URL?

    @Environment(\.databaseContext) private var databaseContext
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @EnvironmentObject private var metadataImportManager: MetadataImportManager
    @EnvironmentObject private var eventCenter: EventCenter

    private var isOneDrive: Bool {
        libraryFolderManager.oneDriveRootItemId != nil
    }

    var body: some View {
        Group {
            if let url = oneDriveResolvedURL {
                // OneDrive: downloaded cover available
                CollectionURLThumbnailView(title: folder.name, url: url, showLabel: settingsManager.layout != .col6)
            } else if isOneDrive && coverImageState != .empty && coverImageState != .error {
                // OneDrive: still loading/downloading
                CollectionThumbnailView(title: folder.name, noGradation: true, showLabel: settingsManager.layout != .col6) {
                    ThumbnailLoading()
                }
            } else {
                // Non-OneDrive or OneDrive with empty/error: use existing states
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
        }
        .task(id: folder.id) {
            oneDriveResolvedURL = nil
            if isOneDrive {
                await loadCoverItemOneDrive()
            } else {
                await loadCoverItem()
            }
        }
        .onChange(of: folder) {
            Task {
                if isOneDrive {
                    await loadCoverItemOneDrive()
                } else {
                    await loadCoverItem()
                }
            }
        }
        .onReceive(eventCenter.publisher) { event in
            if case .folderCacheInvalidated = event {
                Task {
                    if isOneDrive {
                        await loadCoverItemOneDrive()
                    } else {
                        await loadCoverItem()
                    }
                }
            }
        }
    }

    // MARK: - OneDrive path (state-driven, no CacheManager)

    private func loadCoverItemOneDrive() async {
        // Already resolved — nothing to do
        guard oneDriveResolvedURL == nil else { return }

        guard let rootItemId = libraryFolderManager.oneDriveRootItemId,
              let libraryURL = libraryFolderManager.currentLibraryURL
        else {
            await MainActor.run { coverImageState = .error }
            return
        }

        let globalSortOption = settingsManager.globalSortOption

        // Query DB for the folder's cover item
        guard let item = try? await getCoverItemFromDB(globalSortOption: globalSortOption) else {
            // No cover item found in DB.
            // If import is still in progress, stay in loading — folderCacheInvalidated will re-trigger us.
            // If import is done, this folder genuinely has no linked items — show empty.
            let importing = await MainActor.run { metadataImportManager.isImporting }
            if !importing {
                await MainActor.run { coverImageState = .empty }
            }
            return
        }

        let localURL = libraryURL.appending(path: item.thumbnailPath, directoryHint: .notDirectory)

        // If already downloaded locally, use it immediately
        if FileManager.default.fileExists(atPath: localURL.path) {
            await MainActor.run { oneDriveResolvedURL = localURL }
            return
        }

        // Download on demand (OneDriveImageDownloader deduplicates concurrent calls)
        let downloadedURL = await OneDriveImageDownloader.shared.ensureImageExists(
            rootItemId: rootItemId,
            relativePath: item.thumbnailPath,
            localBaseURL: libraryURL
        )

        await MainActor.run {
            if let downloadedURL {
                oneDriveResolvedURL = downloadedURL
            } else {
                coverImageState = .error
            }
        }
    }

    // MARK: - Non-OneDrive path (CacheManager, unchanged from original)

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
            // First try to use the folder's specified cover item
            if let coverItemId = folder.coverItemId {
                if let item = try Item
                    .filter(Column("libraryId") == folder.libraryId)
                    .filter(Column("itemId") == coverItemId)
                    .filter(Column("isDeleted") == false)
                    .fetchOne(db)
                {
                    return item
                }
            }

            // Then try to get direct child items
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

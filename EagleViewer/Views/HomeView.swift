//
//  HomeView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

struct HomeView: View {
    @Environment(\.library) private var library
    @State private var showingLibraries = false
    @State private var showingSettings = false
    @Query(RootFoldersRequest(libraryId: nil, folderSortOption: .defaultValue)) private var folders: [Folder]

    @EnvironmentObject private var navigationManager: NavigationManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var searchManager: SearchManager
    @EnvironmentObject private var eventCenter: EventCenter
    @Environment(\.repositories) private var repositories

    private var isSearchEmpty: Bool {
        $folders.searchText.wrappedValue.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isSearchEmpty {
                    CollectionLinksView()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Folders")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    FolderListView(
                        folders: folders,
                        placeholderType: isSearchEmpty ? .default : .search,
                        onSelected: onFolderSelected
                    )
                }
            }
        }
        .safeAreaPadding(.bottom, 52)
        .searchDismissible()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    showingLibraries = true
                }) {
                    HStack(spacing: 4) {
                        Text(library.name)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .legacyAccentForeground()
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                RefreshButton()
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showingLibraries) {
            LibrariesView()
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
        }
        .onChange(of: library.id, initial: true) {
            $folders.libraryId.wrappedValue = library.id
        }
        .onChange(of: settingsManager.folderSortOption, initial: true) {
            $folders.folderSortOption.wrappedValue = settingsManager.folderSortOption
        }
        .onAppear {
            searchManager.setSearchHandler(initialSearchText: $folders.searchText.wrappedValue) { text in
                $folders.searchText.wrappedValue = text
            }
        }
        .onReceive(eventCenter.publisher) { event in
            if case .navigationWillReset = event {
                $folders.searchText.wrappedValue = ""
                searchManager.clearSearch()
            }
        }
    }

    private func onFolderSelected(_ folder: Folder) {
        let searchText = searchManager.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            Task {
                try? await repositories.searchHistory.save(
                    SearchHistory(
                        libraryId: library.id,
                        searchHistoryType: .folder,
                        searchText: searchText,
                        searchedAt: Date()
                    )
                )
            }
        }
    }
}

struct RootFoldersRequest: ValueObservationQueryable {
    var libraryId: Int64?
    var folderSortOption: FolderSortOption
    var searchText: String = ""

    static var defaultValue: [Folder] { [] }

    func fetch(_ db: Database) throws -> [Folder] {
        guard let libraryId else {
            return []
        }

        return try FolderQuery.rootFolders(
            libraryId: libraryId,
            folderSortOption: folderSortOption,
            searchText: searchText
        ).fetchAll(db)
    }
}

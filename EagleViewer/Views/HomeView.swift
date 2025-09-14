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
    @State private var foldersRequest = RootFoldersRequest(libraryId: nil, folderSortOption: .defaultValue)

    @EnvironmentObject private var navigationManager: NavigationManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var searchManager: SearchManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if searchManager.debouncedSearchText.isEmpty {
                    CollectionLinksView()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Folders")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                    FolderListRequestView(
                        request: $foldersRequest,
                        placeholderType: searchManager.debouncedSearchText.isEmpty ? .default : .search
                    )
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: {
                    showingLibraries = true
                }) {
                    HStack(spacing: 4) {
                        Text(library.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
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
            foldersRequest.libraryId = library.id
        }
        .onChange(of: settingsManager.folderSortOption, initial: true) {
            foldersRequest.folderSortOption = settingsManager.folderSortOption
        }
        .onAppear {
            searchManager.setSearchHandler { text in
                foldersRequest.searchText = text
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

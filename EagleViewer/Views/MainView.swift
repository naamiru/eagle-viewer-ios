//
//  MainView.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import SwiftUI

struct MainView: View {
    @Environment(\.library) private var library
    @Environment(\.repositories) private var repositories
    @EnvironmentObject private var metadataImportManager: MetadataImportManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @EnvironmentObject private var eventCenter: EventCenter
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var searchManager = SearchManager()
    @State private var libraryAccessTask: Task<Void, Error>?

    var body: some View {
        ZStack {
            NavigationStack(path: $navigationManager.path) {
                HomeView()
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .folder(let id):
                            FolderDetailView(id: id)
                        case .all:
                            AllCollectionView()
                        case .uncategorized:
                            UncategorizedCollectionView()
                        case .random:
                            RandomCollectionView()
                        }
                    }
            }

            VStack {
                Spacer()
                BottomBarView()
            }
        }
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .bottom) {
            if searchManager.isSearchActive {
                SearchBottomBarView()
            }
        }
        .environmentObject(navigationManager)
        .environmentObject(searchManager)
        .onChange(of: library, initial: true) { oldLibrary, newLibrary in
            if oldLibrary.id != newLibrary.id // library changed
                || oldLibrary == newLibrary // inital call
                || oldLibrary.bookmarkData != newLibrary.bookmarkData // folder changed
            {
                // automatic import

                // cancel running importing task
                libraryAccessTask?.cancel()
                metadataImportManager.cancelImporting()

                // run only initial import for local libarary
                if library.useLocalStorage && library.lastImportStatus != .none {
                    return
                }

                libraryAccessTask = Task {
                    // start importing after folder access established
                    _ = try await libraryFolderManager.getActiveLibraryURL()
                    try Task.checkCancellation()
                    await startImportingForCurrentLibrary()
                }
            }
        }
        .onChange(of: metadataImportManager.importProgress) {
            if metadataImportManager.isImporting {
                eventCenter.post(.importProgressChanged)
            }
        }
    }

    private func startImportingForCurrentLibrary() async {
        await metadataImportManager.startImporting(
            library: library,
            activeLibraryURL: libraryFolderManager.activeLibraryURL,
            dbWriter: repositories.dbWriter
        )
    }
}

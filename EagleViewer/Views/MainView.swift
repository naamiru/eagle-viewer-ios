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
    @State private var libraryAccessTask: Task<Void, Error>?
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
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

            BottomBarView()
        }
        .overlay(alignment: .bottom) {
            if isSearchPresented {
                SearchBottomBarView(
                    searchText: $searchText,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    onCancel: {
                        isSearchPresented = false
                        searchText = ""
                        isSearchFieldFocused = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .horizontal)
        .environmentObject(navigationManager)
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
        .onReceive(eventCenter.publisher) { event in
            if case .searchToggled = event {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchPresented.toggle()
                    if isSearchPresented {
                        isSearchFieldFocused = true
                    } else {
                        searchText = ""
                        isSearchFieldFocused = false
                    }
                }
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

struct SearchBottomBarView: View {
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)

            Button("Cancel") {
                onCancel()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(UIColor.separator)),
            alignment: .top
        )
    }
}

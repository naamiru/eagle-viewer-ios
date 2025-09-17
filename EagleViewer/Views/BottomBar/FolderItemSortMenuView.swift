//
//  FolderItemSortMenuView.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import GRDB
import GRDBQuery
import SwiftUI

struct FolderItemSortMenuView: View {
    let folderId: String

    @State private var request: FolderRequest

    @Environment(\.library) private var library

    init(folderId: String) {
        self.folderId = folderId
        _request = State(initialValue: FolderRequest(libraryId: 0, folderId: folderId))
    }

    var body: some View {
        FolderItemSortMenuInnerView(request: $request)
            .onChange(of: folderId, initial: true) {
                request.folderId = folderId
            }
            .onChange(of: library.id, initial: true) {
                request.libraryId = library.id
            }
    }
}

struct FolderItemSortMenuInnerView: View {
    @Query<FolderRequest> private var folder: Folder?
    @Environment(\.repositories) private var repositories
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var eventCenter: EventCenter

    init(request: Binding<FolderRequest>) {
        _folder = Query(request)
    }

    var body: some View {
        if let folder {
            Menu {
                ForEach(FolderItemSortType.allCases.reversed(), id: \.self) { type in
                    let sortOption = folder.sortOption(globalSortOption: settingsManager.globalSortOption)
                    Button(action: {
                        Task {
                            let newSortOption: FolderItemSortOption
                            if sortOption.type == type {
                                newSortOption = FolderItemSortOption(type: type, ascending: !sortOption.ascending)

                                if type == .global {
                                    settingsManager.setGlobalSortOption(.init(type: settingsManager.globalSortOption.type, ascending: newSortOption.ascending))
                                    eventCenter.post(.globalSortChanged)
                                }
                            } else {
                                newSortOption = FolderItemSortOption(type: type, ascending: true)
                            }
                            try await repositories.folder.updateSortOption(
                                libraryId: folder.libraryId,
                                folderId: folder.folderId,
                                sortOption: newSortOption
                            )
                            eventCenter.post(.folderSortChanged(folder))
                        }
                    }) {
                        if sortOption.type == type {
                            Label(type.displayName, systemImage: sortOption.ascending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(type.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(Color.primary)
                    .frame(width: 30, height: 30)
            }
        } else {
            Button(action: {}) {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(Color.secondary)
                    .frame(width: 30, height: 30)
            }
            .disabled(true)
        }
    }
}

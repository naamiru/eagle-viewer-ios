//
//  FolderListView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

struct FolderListView: View {
    let folders: [Folder]
    let showPlaceholder: Bool

    init(folders: [Folder], showPlaceholder: Bool = false) {
        self.folders = folders
        self.showPlaceholder = showPlaceholder
    }

    var body: some View {
        if folders.isEmpty && showPlaceholder {
            NoFolderView()
        } else {
            AdaptiveGridView(isCollection: true) {
                ForEach(folders) { folder in
                    NavigationLink(value: NavigationDestination.folder(folder.id)) {
                        FolderThumbnailViewWithCache(folder: folder)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

struct FolderListRequestView<T: ValueObservationQueryable>: View where T.Value == [Folder], T.Context == DatabaseContext {
    @Query<T> var folders: [Folder]
    let showPlaceholder: Bool

    init(request: Binding<T>, showPlaceholder: Bool = false) {
        _folders = Query(request, in: \.databaseContext)
        self.showPlaceholder = showPlaceholder
    }

    var body: some View {
        FolderListView(folders: folders, showPlaceholder: showPlaceholder)
    }
}

struct NoFolderView: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "folder")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("No Folders")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 200)
    }
}

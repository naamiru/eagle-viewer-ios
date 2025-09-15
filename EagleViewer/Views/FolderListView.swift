//
//  FolderListView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

enum PlaceholderType {
    case none
    case search
    case `default`
}

struct FolderListView: View {
    let folders: [Folder]
    let placeholderType: PlaceholderType

    init(folders: [Folder], placeholderType: PlaceholderType = .none) {
        self.folders = folders
        self.placeholderType = placeholderType
    }

    var body: some View {
        if folders.isEmpty && placeholderType != .none {
            switch placeholderType {
            case .search:
                NoResultsView()
            case .default:
                NoFolderView()
            case .none:
                EmptyView()
            }
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
    let placeholderType: PlaceholderType

    init(request: Binding<T>, placeholderType: PlaceholderType = .none) {
        _folders = Query(request, in: \.databaseContext)
        self.placeholderType = placeholderType
    }

    var body: some View {
        FolderListView(folders: folders, placeholderType: placeholderType)
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

struct NoResultsView: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("Nothing Found")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 200)
    }
}

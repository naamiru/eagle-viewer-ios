import GRDB
import GRDBQuery
import SwiftUI

struct FolderDetailView: View {
    let id: Folder.ID
    @State private var request: FolderRequest

    @EnvironmentObject private var navigationManager: NavigationManager

    init(id: Folder.ID) {
        self.id = id
        _request = State(initialValue: FolderRequest(libraryId: id.libraryId, folderId: id.folderId))
    }

    var body: some View {
        FolderDetailRequestView(request: $request)
            .onChange(of: id.folderId) {
                request.folderId = id.folderId
            }
    }
}

struct FolderDetailRequestView: View {
    @Query<FolderRequest> private var folder: Folder?

    init(request: Binding<FolderRequest>) {
        self._folder = Query(request)
    }

    var body: some View {
        if let folder {
            FolderDetailInnerView(folder: folder)
        }
    }
}

struct FolderDetailInnerView: View {
    let folder: Folder
    @State private var itemsRequest: FolderItemsRequest
    @State private var childFoldersRequest: ChildFoldersRequest

    @EnvironmentObject private var settingsManager: SettingsManager

    init(folder: Folder) {
        self.folder = folder
        self._itemsRequest = State(initialValue: FolderItemsRequest(folder: folder, globalSortOption: GlobalSortOption.defaultValue))
        self._childFoldersRequest = State(initialValue: ChildFoldersRequest(folder: folder, folderSortOption: FolderSortOption.defaultValue))
    }

    var body: some View {
        FolderDetailInnerRequestView(
            itemsRequest: $itemsRequest,
            childFoldersRequest: $childFoldersRequest
        )
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: folder, initial: true) {
            itemsRequest.folder = folder
            childFoldersRequest.folder = folder
        }
        .onChange(of: settingsManager.globalSortOption, initial: true) {
            itemsRequest.globalSortOption = settingsManager.globalSortOption
        }
        .onChange(of: settingsManager.folderSortOption, initial: true) {
            childFoldersRequest.folderSortOption = settingsManager.folderSortOption
        }
    }
}

struct FolderDetailInnerRequestView: View {
    @Query<ChildFoldersRequest> private var childFolders: [Folder]
    @Query<FolderItemsRequest> private var items: [Item]
    @Binding var itemsRequest: FolderItemsRequest
    @Binding var childFoldersRequest: ChildFoldersRequest

    @EnvironmentObject private var searchManager: SearchManager

    init(itemsRequest: Binding<FolderItemsRequest>, childFoldersRequest: Binding<ChildFoldersRequest>) {
        self._itemsRequest = itemsRequest
        self._childFoldersRequest = childFoldersRequest
        _childFolders = Query(childFoldersRequest)
        _items = Query(itemsRequest)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !childFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !items.isEmpty {
                            Text("Subfolders")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                        FolderListView(folders: childFolders, placeholderType: .none)
                    }
                }
                if !items.isEmpty || childFolders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !childFolders.isEmpty {
                            Text("Images")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                        ItemListView(items: items, placeholderType: childFolders.isEmpty ? (searchManager.debouncedSearchText.isEmpty ? .default : .search) : .none)
                            .ignoresSafeArea(edges: .horizontal)
                    }
                }
            }
        }
        .searchDismissible()
        .onAppear {
            searchManager.setSearchHandler { text in
                itemsRequest.searchText = text
                childFoldersRequest.searchText = text
            }
        }
    }
}

struct FolderRequest: ValueObservationQueryable {
    var libraryId: Int64
    var folderId: String

    static var defaultValue: Folder? { nil }

    func fetch(_ db: Database) throws -> Folder? {
        return try Folder
            .filter(Column("libraryId") == libraryId)
            .filter(Column("folderId") == folderId)
            .fetchOne(db)
    }
}

struct ChildFoldersRequest: ValueObservationQueryable {
    var folder: Folder
    var folderSortOption: FolderSortOption
    var searchText: String = ""

    static var defaultValue: [Folder] { [] }

    func fetch(_ db: Database) throws -> [Folder] {
        return try FolderQuery.childFolders(
            libraryId: folder.libraryId,
            parentId: folder.folderId,
            folderSortOption: folderSortOption,
            searchText: searchText
        ).fetchAll(db)
    }
}

struct FolderItemsRequest: ValueObservationQueryable {
    var folder: Folder
    var globalSortOption: GlobalSortOption
    var searchText: String = ""

    static var defaultValue: [Item] { [] }

    func fetch(_ db: Database) throws -> [Item] {
        return try FolderQuery.folderItems(folder: folder, globalSortOption: globalSortOption, searchText: searchText)
            .fetchAll(db)
    }
}

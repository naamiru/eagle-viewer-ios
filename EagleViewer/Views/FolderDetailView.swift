import GRDB
import GRDBQuery
import SwiftUI

struct FolderDetailView: View {
    @Query<FolderRequest> private var folder: Folder?

    @EnvironmentObject private var navigationManager: NavigationManager

    init(id: Folder.ID) {
        _folder = Query(FolderRequest(libraryId: id.libraryId, folderId: id.folderId))
    }

    var body: some View {
        if let folder {
            FolderDetailInnerView(folder: folder)
        }
    }
}

struct FolderDetailInnerView: View {
    let folder: Folder
    @Query<FolderItemsRequest> private var items: [Item]
    @Query<ChildFoldersRequest> private var childFolders: [Folder]

    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var searchManager: SearchManager

    init(folder: Folder) {
        self.folder = folder
        _items = Query(FolderItemsRequest(folder: folder, globalSortOption: GlobalSortOption.defaultValue))
        _childFolders = Query(ChildFoldersRequest(folder: folder, folderSortOption: FolderSortOption.defaultValue))
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
        .safeAreaPadding(.bottom, 52)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: folder, initial: true) {
            $items.folder.wrappedValue = folder
            $childFolders.folder.wrappedValue = folder
        }
        .onChange(of: settingsManager.globalSortOption, initial: true) {
            $items.globalSortOption.wrappedValue = settingsManager.globalSortOption
        }
        .onChange(of: settingsManager.folderSortOption, initial: true) {
            $childFolders.folderSortOption.wrappedValue = settingsManager.folderSortOption
        }
        .onAppear {
            searchManager.setSearchHandler { text in
                $items.searchText.wrappedValue = text
                $childFolders.searchText.wrappedValue = text
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

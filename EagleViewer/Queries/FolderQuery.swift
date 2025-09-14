//
//  FolderQuery.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import GRDB

class FolderQuery {
    static func searchFolders(libraryId: Int64, searchText: String) -> QueryInterfaceRequest<Folder> {
        var query = Folder.filter(Column("libraryId") == libraryId)

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            let keywords = trimmedSearch.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            for keyword in keywords {
                // Escape special characters for SQL LIKE
                let escapedKeyword = keyword
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                query = query.filter(sql: "name LIKE ? ESCAPE '\\'", arguments: ["%\(escapedKeyword)%"])
            }
        }

        return query
    }

    static func rootFolders(libraryId: Int64, folderSortOption: FolderSortOption, searchText: String = "") -> QueryInterfaceRequest<Folder> {
        searchFolders(libraryId: libraryId, searchText: searchText)
            .filter(Column("parentId") == nil)
            .order(sql: SortQuery.folderOrderSQL(by: folderSortOption))
    }

    static func childFolders(libraryId: Int64, parentId: String, folderSortOption: FolderSortOption, searchText: String = "") -> QueryInterfaceRequest<Folder> {
        searchFolders(libraryId: libraryId, searchText: searchText)
            .filter(Column("parentId") == parentId)
            .order(sql: SortQuery.folderOrderSQL(by: folderSortOption))
    }

    static func folderItems(folder: Folder, globalSortOption: GlobalSortOption, searchText: String = "") -> QueryInterfaceRequest<Item> {
        CollectionQuery.searchItems(libraryId: folder.libraryId, searchText: searchText)
            .joining(required: StoredItem.folderItems
                .filter(Column("folderId") == folder.folderId))
            .order(sql: SortQuery.folderItemOrderSQL(
                by: folder.sortOption(globalSortOption: globalSortOption), global: globalSortOption
            ))
            .select(CollectionQuery.itemColumns, as: Item.self)
    }

    static func folderItemsWithDescendantFallback(folder: Folder, globalSortOption: GlobalSortOption) -> SQLRequest<Item> {
        return SQLRequest<Item>(sql: """
        WITH RECURSIVE descendant_folders AS (
            -- Start with direct children of the current folder (depth 2)
            SELECT libraryId, folderId, parentId, 2 as depth
            FROM folder
            WHERE libraryId = ? AND parentId = ?

            UNION ALL

            -- Get grandchildren (depth 3)
            SELECT f.libraryId, f.folderId, f.parentId, df.depth + 1
            FROM folder f
            INNER JOIN descendant_folders df ON f.parentId = df.folderId AND f.libraryId = df.libraryId
            WHERE df.depth < 3  -- Only go to depth 3
        )
        SELECT i.*
        FROM item i
        INNER JOIN folderItem fi ON i.libraryId = fi.libraryId AND i.itemId = fi.itemId
        INNER JOIN descendant_folders df ON fi.libraryId = df.libraryId AND fi.folderId = df.folderId
        WHERE i.isDeleted = 0
        ORDER BY df.depth
        LIMIT 1
        """, arguments: [folder.libraryId, folder.folderId])
    }
}

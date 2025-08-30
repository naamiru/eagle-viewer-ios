//
//  FolderQuery.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import GRDB

class FolderQuery {
    static func rootFolders(libraryId: Int64, folderSortOption: FolderSortOption) -> QueryInterfaceRequest<Folder> {
        Folder
            .filter(Column("libraryId") == libraryId)
            .filter(Column("parentId") == nil)
            .order(sql: SortQuery.folderOrderSQL(by: folderSortOption))
    }

    static func childFolders(libraryId: Int64, parentId: String, folderSortOption: FolderSortOption) -> QueryInterfaceRequest<Folder> {
        Folder
            .filter(Column("libraryId") == libraryId)
            .filter(Column("parentId") == parentId)
            .order(sql: SortQuery.folderOrderSQL(by: folderSortOption))
    }

    static func folderItems(folder: Folder, globalSortOption: GlobalSortOption) -> QueryInterfaceRequest<Item> {
        Item
            .filter(Column("libraryId") == folder.libraryId)
            .filter(Column("isDeleted") == false)
            .joining(required: Item.folderItems
                .filter(Column("folderId") == folder.folderId)
            )
            .order(sql: SortQuery.folderItemOrderSQL(
                by: folder.sortOption(globalSortOption: globalSortOption), global: globalSortOption)
            )
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

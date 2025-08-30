//
//  CollectionQuery.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB

class CollectionQuery {
    static func allItems(libraryId: Int64, sortOption: GlobalSortOption) -> QueryInterfaceRequest<Item> {
        Item.filter(Column("libraryId") == libraryId)
            .filter(Column("isDeleted") == false)
            .order(sql: SortQuery.itemOrderSQL(by: sortOption))
    }

    static func uncategorizedItems(libraryId: Int64, sortOption: GlobalSortOption) -> QueryInterfaceRequest<Item> {
        return Item
            .filter(Column("libraryId") == libraryId)
            .filter(Column("isDeleted") == false)
            .filter(sql: "NOT EXISTS (SELECT * FROM folderItem WHERE libraryId = item.libraryId AND itemId = item.itemId)")
            .order(sql: SortQuery.itemOrderSQL(by: sortOption))
    }

    static func randomItems(libraryId: Int64) -> QueryInterfaceRequest<Item> {
        Item.filter(Column("libraryId") == libraryId)
            .filter(Column("isDeleted") == false)
            .order(sql: "RANDOM()")
    }
}

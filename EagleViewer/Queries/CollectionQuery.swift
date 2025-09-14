//
//  CollectionQuery.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB

class CollectionQuery {
    static var itemColumns: [SQLSelectable] {
        [Column("libraryId"), Column("itemId"), Column("name"), Column("ext"),
         Column("height"), Column("width"), Column("noThumbnail"), Column("duration")]
    }

    static func allItems(libraryId: Int64, sortOption: GlobalSortOption, searchText: String = "") -> QueryInterfaceRequest<Item> {
        searchItems(libraryId: libraryId, searchText: searchText)
            .order(sql: SortQuery.itemOrderSQL(by: sortOption))
            .select(itemColumns, as: Item.self)
    }

    static func uncategorizedItems(libraryId: Int64, sortOption: GlobalSortOption, searchText: String = "") -> QueryInterfaceRequest<Item> {
        return searchItems(libraryId: libraryId, searchText: searchText)
            .filter(sql: "NOT EXISTS (SELECT * FROM folderItem WHERE libraryId = item.libraryId AND itemId = item.itemId)")
            .order(sql: SortQuery.itemOrderSQL(by: sortOption))
            .select(itemColumns, as: Item.self)
    }

    static func randomItems(libraryId: Int64, searchText: String = "") -> QueryInterfaceRequest<Item> {
        searchItems(libraryId: libraryId, searchText: searchText)
            .order(sql: "RANDOM()")
            .select(itemColumns, as: Item.self)
    }

    static func searchItems(libraryId: Int64, searchText: String) -> QueryInterfaceRequest<StoredItem> {
        var query = StoredItem
            .filter(Column("libraryId") == libraryId)
            .filter(Column("isDeleted") == false)

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            let keywords = trimmedSearch.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            for keyword in keywords {
                // Escape special characters for SQL LIKE
                let escapedKeyword = keyword
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")

                // Search across name, annotation, and tags
                let nameCondition = "name LIKE ? ESCAPE '\\'"
                let annotationCondition = "annotation LIKE ? ESCAPE '\\'"
                let tagsCondition = "EXISTS (SELECT 1 FROM json_each(tags) WHERE value LIKE ? ESCAPE '\\')"

                let likePattern = "%\(escapedKeyword)%"
                query = query.filter(sql: "(\(nameCondition) OR \(annotationCondition) OR \(tagsCondition))",
                                     arguments: [likePattern, likePattern, likePattern])
            }
        }

        return query
    }
}

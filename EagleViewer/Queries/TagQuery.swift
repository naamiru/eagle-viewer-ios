//
//  TagQuery.swift
//  EagleViewer
//
//  Created on 2025/09/19
//

import GRDB

struct TagCount: FetchableRecord, Decodable {
    var tag: String
    var count: Int
}

class TagQuery {
    static func tagsInAll(
        libraryId: Int64,
        itemSearchText: String,
        tagSearchText: String,
        limit: Int
    ) -> SQLRequest<TagCount> {
        return searchTags(
            libraryId: libraryId,
            itemSearchText: itemSearchText,
            tagSearchText: tagSearchText,
            limit: limit
        )
    }

    static func tagsInUncategorized(
        libraryId: Int64,
        itemSearchText: String,
        tagSearchText: String,
        limit: Int
    ) -> SQLRequest<TagCount> {
        return searchTags(
            libraryId: libraryId,
            itemSearchText: itemSearchText,
            tagSearchText: tagSearchText,
            limit: limit,
            conditions: (
                sql: "NOT EXISTS (SELECT * FROM folderItem WHERE libraryId = item.libraryId AND itemId = item.itemId)",
                arguments: []
            )
        )
    }

    static func tagsInFolder(
        libraryId: Int64,
        folderId: String,
        itemSearchText: String,
        tagSearchText: String,
        limit: Int
    ) -> SQLRequest<TagCount> {
        return searchTags(
            libraryId: libraryId,
            itemSearchText: itemSearchText,
            tagSearchText: tagSearchText,
            limit: limit,
            joinSQL: "LEFT JOIN folderItem ON item.libraryId = folderItem.libraryId AND item.itemId = folderItem.itemId",
            conditions: (
                sql: "folderItem.folderId = ?",
                arguments: [folderId]
            )
        )
    }

    static func searchTags(
        libraryId: Int64,
        itemSearchText: String,
        tagSearchText: String,
        limit: Int,
        joinSQL: String? = nil,
        conditions: (sql: String, arguments: StatementArguments)? = nil
    ) -> SQLRequest<TagCount> {
        var sql = """
            SELECT tags.value as tag, COUNT(item.itemId) AS count
            FROM item, json_each(tags) AS tags
        """
        var arguments: StatementArguments = []

        if let joinSQL {
            sql += " " + joinSQL
        }

        sql += " WHERE item.libraryId = ? AND item.isDeleted = FALSE"
        arguments += [libraryId]

        if let conditions {
            sql += " AND (\(conditions.sql))"
            arguments += conditions.arguments
        }

        for (filterSQL, filterArguments) in ItemQuery.searchTextFilters(searchText: itemSearchText) {
            sql += " AND (\(filterSQL))"
            arguments += filterArguments
        }

        if !tagSearchText.isEmpty {
            let escapedKeyword = tagSearchText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            sql += " AND (tag LIKE ? ESCAPE '\\')"
            arguments += ["%\(escapedKeyword)%"]
        }

        // remove tags they are already in search text
        let searchText = [itemSearchText, tagSearchText].filter { !$0.isEmpty }.joined(separator: " ")
        if !searchText.isEmpty {
            sql += " AND NOT (INSTR(LOWER(?), LOWER(tag)) > 0)"
            arguments += [searchText]
        }

        sql += """
            GROUP BY tags.value
            HAVING count > 0
            ORDER BY count DESC, tag
            LIMIT ?
        """
        arguments += [limit]

        return SQLRequest<TagCount>(sql: sql, arguments: arguments)
    }
}

//
//  Migration.swift
//  EagleViewer
//
//  Created on 2025/08/28
//

import GRDB

enum Migration {
    static func getMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
#if DEBUG
        // Speed up development by nuking the database when migrations change
        // migrator.eraseDatabaseOnSchemaChange = true
#endif
        
        migrator.registerMigration("initial") { db in
            try db.create(table: "library") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("bookmarkData", .blob).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("lastImportedFolderMTime", .integer).notNull().defaults(to: 0)
                t.column("lastImportedItemMTime", .integer).notNull().defaults(to: 0)
                t.column("lastImportStatus", .text).notNull().defaults(to: ImportStatus.none.rawValue)
                t.column("useLocalStorage", .boolean).notNull()
            }
            
            try db.create(table: "folder") { t in
                t.primaryKey {
                    t.belongsTo("library", onDelete: .cascade)
                    t.column("folderId", .text)
                }
                t.column("parentId", .text)
                t.column("name", .text).notNull()
                t.column("nameForSort", .text).notNull()
                t.column("modificationTime", .integer).notNull()
                t.column("manualOrder", .integer).notNull()
                t.column("sortType", .text).notNull().defaults(to: FolderItemSortOption.defaultValue.type.rawValue)
                t.column("sortAscending", .boolean).notNull().defaults(to: FolderItemSortOption.defaultValue.ascending)
            }
            
            try db.create(index: "idx_folder_parent", on: "folder", columns: ["libraryId", "parentId"])
            
            // index for sort
            try db.create(index: "idx_folder_nameForSort", on: "folder", columns: ["libraryId", "nameForSort"])
            try db.create(index: "idx_folder_modificationTime", on: "folder", columns: ["libraryId", "modificationTime"])
            try db.create(index: "idx_folder_manualOrder", on: "folder", columns: ["libraryId", "manualOrder"])
            
            try db.create(table: "item") { t in
                t.primaryKey {
                    t.belongsTo("library", onDelete: .cascade)
                    t.column("itemId", .text)
                }
                t.column("name", .text).notNull()
                t.column("nameForSort", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("btime", .integer).notNull()
                t.column("mtime", .integer).notNull()
                t.column("ext", .text).notNull()
                t.column("isDeleted", .boolean).notNull()
                t.column("modificationTime", .integer).notNull()
                t.column("height", .integer).notNull()
                t.column("width", .integer).notNull()
                t.column("lastModified", .integer).notNull()
                t.column("noThumbnail", .boolean).notNull()
                t.column("star", .integer).notNull()
                t.column("duration", .double).notNull()
            }
            
            // index for sort
            try db.create(index: "idx_item_nameForSort", on: "item", columns: ["libraryId", "isDeleted", "nameForSort"])
            try db.create(index: "idx_item_modificationTime", on: "item", columns: ["libraryId", "isDeleted", "modificationTime"])
            try db.create(index: "idx_item_star", on: "item", columns: ["libraryId", "isDeleted", "star"])
            
            try db.create(table: "folderItem") { t in
                t.primaryKey {
                    t.belongsTo("library", onDelete: .cascade)
                    t.column("folderId", .text)
                    t.column("itemId", .text)
                }
                t.column("orderValue", .text).notNull()
            }
            
            try db.create(index: "idx_folderItem_item", on: "folderItem", columns: ["libraryId", "itemId"])
            
            // Index for efficient manual sort in folder
            try db.create(index: "idx_folderItem_order", on: "folderItem", columns: ["libraryId", "folderId", "orderValue"])
        }

        migrator.registerMigration("add-item-tags-annotation") { db in
            try db.alter(table: "item") { t in
                t.add(column: "tags", .jsonText).defaults(to: "[]")
                t.add(column: "annotation", .text).defaults(to: "")
            }

            // Reset all import timestamps to force re-import of items with new fields
            try db.execute(sql: "UPDATE library SET lastImportedItemMTime = 0")
        }
        
        migrator.registerMigration("create-search-history") { db in
            try db.create(table: "searchHistory") { t in
                t.primaryKey {
                    t.belongsTo("library", onDelete: .cascade)
                    t.column("searchHistoryType", .text)
                    t.column("searchText", .text)
                }
                t.column("searchedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_searchHistory_searchedAt",
                on: "searchHistory",
                columns: ["libraryId", "searchHistoryType", "searchedAt"]
            )
        }

        migrator.registerMigration("add-folder-sort-modified") { db in
            try db.alter(table: "folder") { t in
                t.add(column: "sortModified", .boolean).notNull().defaults(to: false)
            }

            // Update sortModified to true for folders that have a non-default sortType
            let defaultSortType = FolderItemSortOption.defaultValue.type.rawValue
            try db.execute(
                sql: """
                UPDATE folder
                SET sortModified = 1
                WHERE sortType != ?
                """,
                arguments: [defaultSortType]
            )

            // Reset folder import timestamp to force re-import of folders with new sort settings
            try db.execute(sql: "UPDATE library SET lastImportedFolderMTime = 0")
        }

        return migrator
    }
}

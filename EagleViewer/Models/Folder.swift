//
//  Item.swift
//  EagleViewer
//
//  Created on 2025/08/19
//

import Foundation
import GRDB

struct Folder: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    struct ID: Codable, Hashable {
        let libraryId: Int64
        let folderId: String
    }

    var id: ID { ID(libraryId: libraryId, folderId: folderId) }

    var libraryId: Int64
    var folderId: String
    var parentId: String?
    var name: String
    var nameForSort: String
    var modificationTime: Int64
    var manualOrder: Int
    var coverItemId: String?

    var sortType: String = FolderItemSortOption.defaultValue.type.rawValue
    var sortAscending: Bool = FolderItemSortOption.defaultValue.ascending
    var sortModified: Bool = false

    func sortOption(globalSortOption: GlobalSortOption) -> FolderItemSortOption {
        let type = FolderItemSortType(rawValue: sortType) ?? FolderItemSortOption.defaultValue.type
        let ascending = type == .global ? globalSortOption.ascending : sortAscending
        return FolderItemSortOption(
            type: type,
            ascending: ascending
        )
    }

    static let empty: Folder = .init(libraryId: 0, folderId: "", name: "", nameForSort: "", modificationTime: 0, manualOrder: 0, coverItemId: nil)
}

//
//  SortQuery.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import GRDB

class SortQuery {
    // MARK: sort items

    static func itemOrderSQL(by sortOption: GlobalSortOption) -> String {
        let column: String
        let reversed: Bool

        switch sortOption.type {
        case .dateAdded:
            column = "item.modificationTime"
            // newest first
            reversed = true
        case .title:
            column = "item.nameForSort"
            reversed = false
        case .rating:
            column = "item.star"
            // lowest rating first (not reversed)
            reversed = false
        }

        let ascending = sortOption.ascending != reversed
        let primaryOrder = column + (ascending ? "" : " DESC")
        
        // Add secondary sort by modificationTime for rating
        if sortOption.type == .rating {
            let secondaryOrder = "item.modificationTime" + (sortOption.ascending ? " DESC" : "")
            return primaryOrder + ", " + secondaryOrder
        }
        
        return primaryOrder
    }

    // MARK: sort items in a folder

    static func folderItemOrderSQL(by sortOption: FolderItemSortOption, global: GlobalSortOption) -> String {
        let column: String
        let reversed: Bool

        switch sortOption.type {
        case .global:
            return folderItemOrderSQL(by: globalSortOptionToFolderItemSortOption(global), global: global)
        case .manual:
            column = "folderItem.orderValue"
            reversed = true
        case .dateAdded:
            column = "item.modificationTime"
            // newest first
            reversed = true
        case .title:
            column = "item.nameForSort"
            reversed = false
        case .rating:
            column = "item.star"
            // lowest rating first (not reversed)
            reversed = false
        }

        let ascending = sortOption.ascending != reversed
        let primaryOrder = column + (ascending ? "" : " DESC")
        
        // Add secondary sort by modificationTime for rating
        if sortOption.type == .rating {
            let secondaryOrder = "item.modificationTime" + (sortOption.ascending ? " DESC" : "")
            return primaryOrder + ", " + secondaryOrder
        }
        
        return primaryOrder
    }

    private static func globalSortOptionToFolderItemSortOption(_ sortOption: GlobalSortOption) -> FolderItemSortOption {
        switch sortOption.type {
        case .dateAdded:
            return .init(type: .dateAdded, ascending: sortOption.ascending)
        case .title:
            return .init(type: .title, ascending: sortOption.ascending)
        case .rating:
            return .init(type: .rating, ascending: sortOption.ascending)
        }
    }

    // MARK: sort folders

    static func folderOrderSQL(by sortOption: FolderSortOption) -> String {
        let column: String
        let reversed: Bool

        switch sortOption.type {
        case .manual:
            column = "folder.manualOrder"
            reversed = false
        case .dateAdded:
            column = "folder.modificationTime"
            // newest first
            reversed = true
        case .title:
            column = "folder.nameForSort"
            reversed = false
        }

        let ascending = sortOption.ascending != reversed
        return column + (ascending ? "" : " DESC")
    }
}

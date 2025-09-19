//
//  SearchHistory.swift
//  EagleViewer
//
//  Created on 2025/09/19
//

import Foundation
import GRDB

enum SearchHistoryType: String, Codable {
    case folder
    case item
}

struct SearchHistory: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    struct ID: Codable, Hashable {
        let libraryId: Int64
        let searchHistoryType: SearchHistoryType
        let searchText: String
    }

    var id: ID { ID(libraryId: libraryId, searchHistoryType: searchHistoryType, searchText: searchText) }

    var libraryId: Int64
    var searchHistoryType: SearchHistoryType
    var searchText: String

    var searchedAt: Date

    static let databaseTableName = "searchHistory"
}

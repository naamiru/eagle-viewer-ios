//
//  SearchHistoryRepository.swift
//  EagleViewer
//
//  Created on 2025/09/19
//

import Foundation
import GRDB
import GRDBQuery

struct SearchHistoryRepository {
    private let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    func save(_ searchHistory: SearchHistory) async throws {
        try await dbWriter.write { db in
            var history = searchHistory
            history.searchedAt = Date()

            try history.save(db, onConflict: .replace)

            let count = try SearchHistory
                .filter(Column("libraryId") == searchHistory.libraryId)
                .filter(Column("searchHistoryType") == searchHistory.searchHistoryType.rawValue)
                .fetchCount(db)

            if count > 100 {
                let oldestToDelete = count - 100
                let oldestHistories = try SearchHistory
                    .filter(Column("libraryId") == searchHistory.libraryId)
                    .filter(Column("searchHistoryType") == searchHistory.searchHistoryType.rawValue)
                    .order(Column("searchedAt").asc)
                    .limit(oldestToDelete)
                    .fetchAll(db)

                for oldHistory in oldestHistories {
                    try oldHistory.delete(db)
                }
            }
        }
    }

    func deleteSearchHistory(_ searchHistory: SearchHistory) async throws {
        _ = try await dbWriter.write { db in
            try searchHistory.delete(db)
        }
    }
}

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
        }
    }
}

//
//  FolderRepository.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import Foundation
import GRDB

struct FolderRepository {
    private let dbWriter: any DatabaseWriter
    
    init(_ dbWriter: some DatabaseWriter) {
        self.dbWriter = dbWriter
    }
    
    func updateSortOption(libraryId: Int64, folderId: String, sortOption: FolderItemSortOption) async throws {
        try await dbWriter.write { db in
            _ = try Folder
                .filter(Column("libraryId") == libraryId)
                .filter(Column("folderId") == folderId)
                .updateAll(db, [
                    Column("sortType").set(to: sortOption.type.rawValue),
                    Column("sortAscending").set(to: sortOption.ascending)
                ])
        }
    }
}
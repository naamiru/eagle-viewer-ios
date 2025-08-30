//
//  LibraryRepository.swift
//  EagleViewer
//
//  Created on 2025/08/19
//

import Foundation
import GRDB

struct LibraryRepository {
    private let dbWriter: any DatabaseWriter

    init(_ dbWriter: some DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    func create(name: String, bookmarkData: Data, useLocalStorage: Bool) async throws -> Library {
        try await dbWriter.write { db in
            let maxSortOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sortOrder), -1) FROM library") ?? -1
            let library = try NewLibrary(name: name, bookmarkData: bookmarkData, sortOrder: maxSortOrder + 1, useLocalStorage: useLocalStorage).insertAndFetch(db, as: Library.self)
            return library
        }
    }

    func delete(id: Int64) async throws {
        // First get the library to check if it uses local storage
        let library = try await dbWriter.read { db in
            try Library.fetchOne(db, id: id)
        }

        try await dbWriter.write { db in
            _ = try Library.deleteOne(db, id: id)
        }

        // Clean up local storage if it was used
        if let library = library, library.useLocalStorage {
            try? LocalImageStorageManager.shared.removeLocalStorage(for: library.id)
        }
    }

    func updateSortOrders(_ libraries: [Library]) async throws {
        try await dbWriter.write { db in
            for (index, library) in libraries.enumerated() {
                var updatedLibrary = library
                try updatedLibrary.updateChanges(db) {
                    $0.sortOrder = index
                }
            }
        }
    }

    func updateFolder(id: Int64, name: String, bookmarkData: Data) async throws {
        try await dbWriter.write { db in
            // Fetch current library to check if bookmarkData changed
            guard let currentLibrary = try Library.fetchOne(db, id: id) else {
                return
            }
            
            // Skip update if bookmarkData is unchanged
            if currentLibrary.bookmarkData == bookmarkData {
                return
            }
            
            _ = try Library.filter(Column("id") == id).updateAll(db, [
                Column("name").set(to: name),
                Column("bookmarkData").set(to: bookmarkData),
                Column("lastImportedFolderMTime").set(to: 0),
                Column("lastImportedItemMTime").set(to: 0)
            ])
        }
    }
}

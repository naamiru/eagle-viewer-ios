//
//  Repositories.swift
//  EagleViewer
//
//  Created on 2025/08/19
//

import GRDB
import GRDBQuery
import OSLog
import SwiftUI

struct Repositories {
    // DatabasePool for app, in-memory DatabaseQueue for preview
    let dbWriter: any DatabaseWriter

    let library: LibraryRepository
    let folder: FolderRepository
    let searchHistory: SearchHistoryRepository

    init(_ dbWriter: some DatabaseWriter) throws {
        self.dbWriter = dbWriter
        library = LibraryRepository(dbWriter)
        folder = FolderRepository(dbWriter)
        searchHistory = SearchHistoryRepository(dbWriter)

        let migrator = Migration.getMigrator()
        try migrator.migrate(dbWriter)
    }

    public var reader: any DatabaseReader {
        dbWriter
    }

    // Returns an on-disk repositories for the application.
    public static func disk() throws -> Repositories {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let directoryURL = appSupportURL.appending(path: "Database", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // Open or create the database
        let databaseURL = directoryURL.appending(path: "db.sqlite", directoryHint: .notDirectory)

        var config = Configuration()

#if DEBUG
        config.prepareDatabase { db in
            db.trace { event in
                Logger.sql.debug("\(event)")
            }
        }
        config.publicStatementArguments = true
#endif

        let db = try DatabasePool(path: databaseURL.path, configuration: config)

        return try Repositories(db)
    }

    // Returns an empty in-memory repositories, for previews and tests.
    public static func empty() -> Repositories {
        return try! Repositories(DatabaseQueue())
    }
}

private struct RepositoriesKey: EnvironmentKey {
    // The default appDatabase is an empty in-memory repository.
    static let defaultValue = Repositories.empty()
}

extension EnvironmentValues {
    fileprivate(set) var repositories: Repositories {
        get { self[RepositoriesKey.self] }
        set { self[RepositoriesKey.self] = newValue }
    }
}

extension View {
    // Sets both the `repositories` (for writes) and `databaseContext`
    // (for `@Query`) environment values.
    func repositories(_ repositories: Repositories) -> some View {
        environment(\.repositories, repositories)
            .databaseContext(.readOnly { repositories.reader })
    }
}

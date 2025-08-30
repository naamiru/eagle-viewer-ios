//
//  Library.swift
//  EagleViewer
//
//  Created on 2025/08/22
//

import Foundation
import GRDB

enum ImportStatus: String, Codable, CaseIterable {
    case none // Never imported
    case success // Last import was successful
    case failed // Last import failed
    case cancelled // Last import was cancelled

    var displayText: String {
        switch self {
        case .none: return String(localized: "Not Synced")
        case .success: return String(localized: "Completed")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }
}

struct NewLibrary: Codable, FetchableRecord, PersistableRecord {
    static var databaseTableName: String { Library.databaseTableName }

    var name: String
    var bookmarkData: Data
    var sortOrder: Int
    var useLocalStorage: Bool
}

struct Library: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    var id: Int64
    var name: String
    var bookmarkData: Data
    var sortOrder: Int
    var lastImportedFolderMTime: Int64
    var lastImportedItemMTime: Int64
    var lastImportStatus: ImportStatus
    var useLocalStorage: Bool
}

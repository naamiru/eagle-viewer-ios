//
//  Library.swift
//  EagleViewer
//
//  Created on 2025/08/22
//

import Foundation
import GRDB

enum LibrarySource: Codable, Equatable {
    case file(bookmarkData: Data)
    case gdrive(fileId: String)

    private enum Kind: String, Codable { case file, gdrive }
    private struct Box: Codable {
        let kind: Kind
        let bookmarkData: Data?
        let fileId: String?
    }

    init(from decoder: Decoder) throws {
        let b = try Box(from: decoder)
        switch b.kind {
        case .file:
            self = .file(bookmarkData: b.bookmarkData ?? Data())
        case .gdrive:
            self = .gdrive(fileId: b.fileId ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        let box: Box
        switch self {
        case .file(let bookmarkData):
            box = Box(kind: .file, bookmarkData: bookmarkData, fileId: nil)
        case .gdrive(let fileId):
            box = Box(kind: .gdrive, bookmarkData: nil, fileId: fileId)
        }
        try box.encode(to: encoder)
    }
}

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

protocol LibrarySourceProvider {
    var sourceData: Data { get set }
}

extension LibrarySourceProvider {
    var source: LibrarySource {
        get {
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(LibrarySource.self, from: sourceData)
            } catch {
                // Fallback for legacy data that was just bookmark data
                return .file(bookmarkData: sourceData)
            }
        }
        set {
            do {
                let encoder = JSONEncoder()
                sourceData = try encoder.encode(newValue)
            } catch {
                // Fallback - should not happen
                sourceData = Data()
            }
        }
    }
}

struct NewLibrary: Codable, FetchableRecord, PersistableRecord, LibrarySourceProvider {
    static var databaseTableName: String { Library.databaseTableName }

    var name: String
    var sourceData: Data
    var sortOrder: Int
    var useLocalStorage: Bool
}

struct Library: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord, LibrarySourceProvider {
    var id: Int64
    var name: String
    var sourceData: Data
    var sortOrder: Int
    var lastImportedFolderMTime: Int64
    var lastImportedItemMTime: Int64
    var lastImportStatus: ImportStatus
    var useLocalStorage: Bool
}

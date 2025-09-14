//
//  Item.swift
//  EagleViewer
//
//  Created on 2025/08/19
//

import Foundation
import GRDB

protocol ItemPathProvider {
    var itemId: String { get }
    var name: String { get }
    var ext: String { get }
    var noThumbnail: Bool { get }
}

extension ItemPathProvider {
    var imagePath: String {
        "images/\(itemId).info/\(name).\(ext)"
    }

    var thumbnailPath: String {
        if noThumbnail {
            // Use original item file
            return imagePath
        } else {
            // Use thumbnail
            return "images/\(itemId).info/\(name)_thumbnail.png"
        }
    }
}

struct StoredItem: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, ItemPathProvider {
    static var databaseTableName: String { Item.databaseTableName }

    var id: Item.ID { .init(libraryId: libraryId, itemId: itemId) }

    var libraryId: Int64
    var itemId: String
    var name: String
    var nameForSort: String
    var size: Int
    var btime: Int64
    var mtime: Int64
    var ext: String
    var isDeleted: Bool
    var modificationTime: Int64
    var height: Int
    var width: Int
    var lastModified: Int64
    var noThumbnail: Bool
    var star: Int
    var duration: Double
    var tags: [String]
    var annotation: String
}

extension StoredItem: TableRecord {
    static let folderItems = hasMany(FolderItem.self, using: ForeignKey(["libraryId", "itemId"]))
}

struct Item: Codable, Identifiable, FetchableRecord, Hashable, ItemPathProvider {
    struct ID: Codable, Hashable {
        let libraryId: Int64
        let itemId: String
    }

    var id: ID { .init(libraryId: libraryId, itemId: itemId) }

    var libraryId: Int64
    var itemId: String
    var name: String
    var ext: String
    var height: Int
    var width: Int
    var noThumbnail: Bool
    var duration: Double
}

extension Item: TableRecord {
    static let folderItems = hasMany(FolderItem.self, using: ForeignKey(["libraryId", "itemId"]))
}

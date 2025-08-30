//
//  Item.swift
//  EagleViewer
//
//  Created on 2025/08/19
//

import Foundation
import GRDB

struct Item: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable {
    struct ID: Codable, Hashable {
        let libraryId: Int64
        let itemId: String
    }

    var id: ID { ID(libraryId: libraryId, itemId: itemId) }

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

extension Item: TableRecord {
    static let folderItems = hasMany(FolderItem.self, using: ForeignKey(["libraryId", "itemId"]))
}

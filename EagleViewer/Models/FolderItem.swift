//
//  FolderItem.swift
//  EagleViewer
//
//  Created on 2025/08/20
//

import Foundation
import GRDB

struct FolderItem: Codable, Identifiable, FetchableRecord, PersistableRecord {
    struct ID: Codable, Hashable {
        let libraryId: Int64
        let folderId: String
        let itemId: String
    }
    
    var id: ID { ID(libraryId: libraryId, folderId: folderId, itemId: itemId) }
    
    let libraryId: Int64
    let folderId: String
    let itemId: String
    let orderValue: String
    
    static let databaseTableName = "folderItem"
}
//
//  MetadataImporter.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Foundation
import GRDB
import OSLog

struct MetadataImporter {
    /// Converts a title to Eagle's special sort format
    /// Extracts digit sequences and replaces them with left zero-padded 19-character values
    private func nameForSort(from name: String) -> String {
        let regex = try! NSRegularExpression(pattern: "\\d+", options: [])
        let nsString = name as NSString
        let matches = regex.matches(in: name, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var result = name
        var offset = 0
        
        for match in matches {
            let range = NSRange(location: match.range.location + offset, length: match.range.length)
            let matchedString = (result as NSString).substring(with: range)
            
            // Convert to integer and back to get clean number
            if let number = Int(matchedString) {
                let paddedNumber = String(format: "%019d", number)
                result = (result as NSString).replacingCharacters(in: range, with: paddedNumber)
                offset += paddedNumber.count - match.range.length
            }
        }
        
        return result
    }

    struct MetadataJSON: Decodable {
        let folders: [FolderJSON]
        let modificationTime: Int64
    }
    
    struct FolderJSON: Decodable {
        let id: String?
        let name: String?
        let modificationTime: Int64?
        let children: [FolderJSON]?
    }
    
    struct ItemMetadataJSON: Decodable {
        let name: String?
        let size: Int?
        let btime: Int64?
        let mtime: Int64?
        let ext: String?
        let isDeleted: Bool?
        let modificationTime: Int64?
        let height: Int?
        let width: Int?
        let lastModified: Int64?
        let noThumbnail: Bool?
        let star: Int?
        let duration: Double?
        let folders: [String]?
        let order: [String: String]?
    }
    
    struct MTimeJSON: Decodable {
        var itemTimes: [String: Int64]
        let totalCount: Int64
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let dict = try container.decode([String: Int64].self)
            
            // Extract "all" key for total count
            self.totalCount = dict["all"] ?? 0
            
            // Remove "all" key and use remaining as itemTimes
            var times = dict
            times.removeValue(forKey: "all")
            self.itemTimes = times
        }
    }
    
    /// Import all data from Eagle library metadata (folders and items)
    /// - Parameters:
    ///   - dbWriter: Database writer for transaction management
    ///   - libraryId: ID of the library to import data for
    ///   - libraryUrl: Security-scoped URL to the Eagle library (must be already activated)
    ///   - localUrl: Optional URL to local storage for copying images (if useLocalStorage)
    ///   - progressHandler: Callback to report import progress (0.0 to 1.0)
    func importAll(
        dbWriter: DatabaseWriter,
        libraryId: Int64,
        libraryUrl: URL,
        localUrl: URL?,
        progressHandler: @escaping (Double) async -> Void
    ) async throws {
        // Import folders first (assuming folders are 10% of the work)
        try await importFolders(
            dbWriter: dbWriter,
            libraryId: libraryId,
            libraryUrl: libraryUrl
        )
        
        await progressHandler(0.1) // 10% done after folders
        
        try Task.checkCancellation()
        
        // Import items (90% of the work)
        try await importItems(
            dbWriter: dbWriter,
            libraryId: libraryId,
            libraryUrl: libraryUrl,
            localUrl: localUrl,
            progressHandler: { itemProgress in
                // Convert item progress [0,1] to overall progress [0.1,1]
                await progressHandler(0.1 + 0.9 * itemProgress)
            }
        )
    }
    
    /// Import items from Eagle library metadata
    /// - Parameters:
    ///   - dbWriter: Database writer for transaction management
    ///   - libraryId: ID of the library to import items for
    ///   - libraryUrl: Security-scoped URL to the Eagle library (must be already activated)
    ///   - localUrl: Optional URL to local storage for copying images (if useLocalStorage)
    ///   - progressHandler: Callback to report import progress
    func importItems(
        dbWriter: DatabaseWriter,
        libraryId: Int64,
        libraryUrl: URL,
        localUrl: URL?,
        progressHandler: @escaping (Double) async -> Void
    ) async throws {
        Logger.app.debug("Starting item import for library \(libraryId)")
        
        // Get the library's last imported item modification time and existing item IDs
        let (lastImportedItemMTime, existingItemIds) = try await dbWriter.read { db in
            let lastMTime = try Int64.fetchOne(
                db,
                sql: "SELECT lastImportedItemMTime FROM library WHERE id = ?",
                arguments: [libraryId]
            ) ?? 0
            
            let itemIds = try Set(String.fetchAll(
                db,
                sql: "SELECT itemId FROM item WHERE libraryId = ?",
                arguments: [libraryId]
            ))
            
            return (lastMTime, itemIds)
        }
        
        // Get all item times including those not in mtime.json
        let allItemTimes = try await getAllItemTimes(
            libraryUrl: libraryUrl,
            existingDbItemIds: existingItemIds
        )
        
        // Find items that need to be updated, sorted by modification time
        let itemsToUpdate = allItemTimes
            .filter { _, modificationTime in modificationTime > lastImportedItemMTime }
            .sorted { $0.value < $1.value }
            .map { $0.key }
        
        if !itemsToUpdate.isEmpty {
            Logger.app.debug("Updating \(itemsToUpdate.count) items")
            
            let totalItems = itemsToUpdate.count
            var processedItems = 0
            
            // Process items in batches, each in its own transaction
            for batch in itemsToUpdate.chunks(ofSize: 100) {
                // Load metadata for all items in batch first
                let batchMetadata: [(itemId: String, metadata: ItemMetadataJSON)] = try await withThrowingTaskGroup(of: (String, ItemMetadataJSON).self) { group in
                    for itemId in batch {
                        group.addTask {
                            let metadata = try await loadItemMetadata(libraryUrl: libraryUrl, itemId: itemId)
                            return (itemId, metadata)
                        }
                    }
                    
                    var results: [(itemId: String, metadata: ItemMetadataJSON)] = []
                    for try await (itemId, metadata) in group {
                        results.append((itemId: itemId, metadata: metadata))
                    }
                    return results
                }
                
                // Build Item instances from metadata
                let batchItems: [(item: Item, metadata: ItemMetadataJSON)] = batchMetadata.map { itemId, metadata in
                    let item = buildItem(libraryId: libraryId, itemId: itemId, metadata: metadata)
                    return (item: item, metadata: metadata)
                }
                
                // Copy images to local storage if localUrl provided
                if let localUrl = localUrl {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (item, _) in batchItems {
                            group.addTask {
                                try await copyItemImages(
                                    item: item,
                                    libraryUrl: libraryUrl,
                                    localUrl: localUrl
                                )
                            }
                        }
                        
                        for try await _ in group {
                            // Wait for all copies to complete
                        }
                    }
                }
                
                try Task.checkCancellation()
                
                try await dbWriter.write { db in
                    for (item, metadata) in batchItems {
                        try processItem(db: db, item: item, metadata: metadata, existingItemIds: existingItemIds)
                    }
                    
                    // Update timestamp after each batch for efficient retry
                    // Find max timestamp in this batch excluding Int64.max
                    let batchTimestamps = batch.compactMap { itemId in
                        let timestamp = allItemTimes[itemId]
                        return (timestamp != Int64.max) ? timestamp : nil
                    }
                    if let maxBatchTimestamp = batchTimestamps.max() {
                        try db.execute(sql: "UPDATE library SET lastImportedItemMTime = ? WHERE id = ?", arguments: [maxBatchTimestamp, libraryId])
                    }
                }
                
                processedItems += batch.count
                // Report progress from 0 to 0.95 for items (reserve 5% for deletion check)
                let itemProgress = Double(processedItems) / Double(totalItems) * 0.95
                await progressHandler(itemProgress)
                
                // Check for task cancellation between batches
                try Task.checkCancellation()
            }
        } else {
            Logger.app.debug("Skip: No items need updating")
            // Report 95% when no items to update (reserve 5% for deletion check)
            await progressHandler(0.95)
        }
        
        // Determine if we need to check for deletions
        let shouldCheckDeletion: Bool
        if itemsToUpdate.isEmpty {
            // Check if item count has changed
            let currentItemCount = try await dbWriter.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item WHERE libraryId = ?", arguments: [libraryId]) ?? 0
            }
            shouldCheckDeletion = currentItemCount != allItemTimes.count
        } else {
            shouldCheckDeletion = true
        }
        
        // Final transaction for cleanup and timestamp update
        try await dbWriter.write { db in
            if shouldCheckDeletion {
                // Create temporary table for current item IDs
                try db.execute(sql: "DROP TABLE IF EXISTS temp_current_items")
                try db.execute(sql: "CREATE TEMPORARY TABLE temp_current_items (itemId TEXT)")
                
                // Insert all current item IDs using prepared statement
                let insertStatement = try db.makeStatement(sql: "INSERT INTO temp_current_items (itemId) VALUES (?)")
                for (itemId, _) in allItemTimes {
                    try insertStatement.execute(arguments: [itemId])
                }
                
                // Delete removed items and their related records
                try db.execute(sql: "DELETE FROM folderItem WHERE libraryId = ? AND itemId NOT IN (SELECT itemId FROM temp_current_items)", arguments: [libraryId])
                try db.execute(sql: "DELETE FROM item WHERE libraryId = ? AND itemId NOT IN (SELECT itemId FROM temp_current_items)", arguments: [libraryId])
            }
            
            // Update library timestamp (exclude Int64.max values from items not in mtime.json)
            let maxTimestamp = allItemTimes.values.filter { $0 != Int64.max }.max() ?? 0
            try db.execute(sql: "UPDATE library SET lastImportedItemMTime = ? WHERE id = ?", arguments: [maxTimestamp, libraryId])
        }
        
        // Report completion after deletion check
        await progressHandler(1.0)
        
        Logger.app.debug("Item import completed")
    }
    
    /// Get all item times from mtime.json and discover missing items if needed
    /// - Parameters:
    ///   - libraryUrl: Security-scoped URL to the Eagle library
    ///   - existingDbItemIds: Set of item IDs already in the database
    /// - Returns: Dictionary of all item IDs to their modification times
    ///           - New items (not in mtime.json or DB): assigned Int64.max to ensure import
    ///           - Items in DB but not in mtime.json: assigned 0 to preserve without re-import
    private func getAllItemTimes(
        libraryUrl: URL,
        existingDbItemIds: Set<String>
    ) async throws -> [String: Int64] {
        let mtimeURL = libraryUrl.appending(path: "mtime.json", directoryHint: .notDirectory)
        
        let data = try await dataWithoutCache(from: mtimeURL)
        let mtimeData = try JSONDecoder().decode(MTimeJSON.self, from: data)
        
        // Only scan directory if counts don't match (indicating missing items)
        if mtimeData.totalCount != mtimeData.itemTimes.count {
            Logger.app.debug("Item count mismatch: total=\(mtimeData.totalCount), in mtime=\(mtimeData.itemTimes.count), scanning for missing items")
            return try await discoverAllItems(
                libraryUrl: libraryUrl,
                existingItemTimes: mtimeData.itemTimes,
                existingDbItemIds: existingDbItemIds
            )
        } else {
            return mtimeData.itemTimes
        }
    }
    
    /// Discover all item directories in the Eagle library and merge with existing mtime data
    /// - Parameters:
    ///   - libraryUrl: Security-scoped URL to the Eagle library
    ///   - existingItemTimes: Existing item modification times from mtime.json
    ///   - existingDbItemIds: Set of item IDs already in the database
    /// - Returns: Merged dictionary including all discovered items
    private func discoverAllItems(
        libraryUrl: URL,
        existingItemTimes: [String: Int64],
        existingDbItemIds: Set<String>
    ) async throws -> [String: Int64] {
        var allItemTimes = existingItemTimes
        let imagesURL = libraryUrl.appending(path: "images", directoryHint: .isDirectory)
        
        guard FileManager.default.fileExists(atPath: imagesURL.path) else {
            Logger.app.debug("Images directory does not exist at \(imagesURL.path)")
            return allItemTimes
        }
        
        let contents = try FileManager.default.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: nil)
        var missingItemsNew: [String] = []
        var missingItemsInDb: [String] = []
        
        for itemURL in contents {
            // Check if it's an .info directory
            if itemURL.lastPathComponent.hasSuffix(".info") {
                // Extract item ID (remove .info suffix)
                let itemId = String(itemURL.lastPathComponent.dropLast(5))
                
                // If this item is not in mtime data
                if allItemTimes[itemId] == nil {
                    if existingDbItemIds.contains(itemId) {
                        // Item exists in DB but not in mtime.json - preserve it with timestamp 0
                        missingItemsInDb.append(itemId)
                        allItemTimes[itemId] = 0
                    } else {
                        // Item is new (not in mtime.json or DB) - import it with max timestamp
                        missingItemsNew.append(itemId)
                        allItemTimes[itemId] = Int64.max
                    }
                }
            }
        }
        
        if !missingItemsNew.isEmpty {
            Logger.app.info("Found \(missingItemsNew.count) new items not in mtime.json or database, adding with max timestamp")
            Logger.app.debug("New items: \(missingItemsNew.joined(separator: ", "))")
        }
        
        if !missingItemsInDb.isEmpty {
            Logger.app.info("Found \(missingItemsInDb.count) items in database but not in mtime.json, preserving with timestamp 0")
            Logger.app.debug("Preserved items: \(missingItemsInDb.joined(separator: ", "))")
        }
        
        return allItemTimes
    }
    
    private func loadItemMetadata(
        libraryUrl: URL,
        itemId: String
    ) async throws -> ItemMetadataJSON {
        let metadataURL = libraryUrl
            .appending(path: "images/\(itemId).info/metadata.json", directoryHint: .notDirectory)
        
        let data = try await dataWithoutCache(from: metadataURL)
        return try JSONDecoder().decode(ItemMetadataJSON.self, from: data)
    }
    
    private func buildItem(
        libraryId: Int64,
        itemId: String,
        metadata: ItemMetadataJSON
    ) -> Item {
        let name = metadata.name ?? ""
        return Item(
            libraryId: libraryId,
            itemId: itemId,
            name: name,
            nameForSort: nameForSort(from: name),
            size: metadata.size ?? 0,
            btime: metadata.btime ?? 0,
            mtime: metadata.mtime ?? 0,
            ext: metadata.ext ?? "",
            isDeleted: metadata.isDeleted ?? false,
            modificationTime: metadata.modificationTime ?? 0,
            height: metadata.height ?? 0,
            width: metadata.width ?? 0,
            lastModified: metadata.lastModified ?? 0,
            noThumbnail: metadata.noThumbnail ?? false,
            star: metadata.star ?? 0,
            duration: metadata.duration ?? 0
        )
    }
    
    private func copyItemImages(
        item: Item,
        libraryUrl: URL,
        localUrl: URL
    ) async throws {
        // Copy main image file
        let sourceImagePath = libraryUrl.appending(path: item.imagePath, directoryHint: .notDirectory)
        let destImagePath = localUrl.appending(path: item.imagePath, directoryHint: .notDirectory)
        
        // Create parent directory
        let destParent = destImagePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destParent, withIntermediateDirectories: true)
        
        // Remove existing file if it exists (to handle broken/changed files)
        if FileManager.default.fileExists(atPath: destImagePath.path) {
            try FileManager.default.removeItem(at: destImagePath)
        }
        
        // Copy image file
        try FileManager.default.copyItem(at: sourceImagePath, to: destImagePath)
        Logger.app.debug("Copied image: \(item.imagePath)")
        
        // Copy thumbnail if it exists and is different from main image
        if !item.noThumbnail {
            let sourceThumbnailPath = libraryUrl.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: sourceThumbnailPath.path) {
                let destThumbnailPath = localUrl.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
                
                // Remove existing thumbnail if it exists
                if FileManager.default.fileExists(atPath: destThumbnailPath.path) {
                    try FileManager.default.removeItem(at: destThumbnailPath)
                }
                
                try FileManager.default.copyItem(at: sourceThumbnailPath, to: destThumbnailPath)
                Logger.app.debug("Copied thumbnail: \(item.thumbnailPath)")
            }
        }
    }
    
    private func processItem(
        db: Database,
        item: Item,
        metadata: ItemMetadataJSON,
        existingItemIds: Set<String> = []
    ) throws {
        // Use insert for new items, save for existing items
        var mutableItem = item
        if existingItemIds.contains(item.itemId) {
            try mutableItem.save(db)
        } else {
            try mutableItem.insert(db)
        }
        
        // Delete existing FolderItem records and create new ones
        try db.execute(sql: "DELETE FROM folderItem WHERE libraryId = ? AND itemId = ?", arguments: [item.libraryId, item.itemId])
        if let folders = metadata.folders {
            for folderId in folders {
                // Use order value from metadata if available, otherwise use modificationTime as default
                let orderValue = metadata.order?[folderId] ?? String(metadata.modificationTime ?? 0)
                
                let folderItem = FolderItem(
                    libraryId: item.libraryId,
                    folderId: folderId,
                    itemId: item.itemId,
                    orderValue: orderValue
                )
                try folderItem.insert(db)
            }
        }
    }
    
    /// Import folders from Eagle library metadata
    /// - Parameters:
    ///   - dbWriter: Database writer for transaction management
    ///   - libraryId: ID of the library to import folders for
    ///   - libraryUrl: Security-scoped URL to the Eagle library (must be already activated)
    func importFolders(
        dbWriter: DatabaseWriter,
        libraryId: Int64,
        libraryUrl: URL
    ) async throws {
        Logger.app.debug("Starting metadata import for library \(libraryId)")
        
        let metadataURL = libraryUrl.appending(path: "metadata.json", directoryHint: .notDirectory)
        
        let data = try await dataWithoutCache(from: metadataURL)
        let metadata = try JSONDecoder().decode(MetadataJSON.self, from: data)
        
        try await dbWriter.write { db in
            // Get the library's last imported modification time
            let lastImportedModificationTime = try Int64.fetchOne(
                db,
                sql: "SELECT lastImportedFolderMTime FROM library WHERE id = ?",
                arguments: [libraryId]
            ) ?? 0
            
            // Skip if metadata hasn't changed
            guard metadata.modificationTime > lastImportedModificationTime else {
                Logger.app.debug("Skip: Metadata hasn't changed")
                return
            }
            
            let existingFolderIds = try Set(
                String.fetchAll(db, sql: "SELECT folderId FROM folder WHERE libraryId = ?", arguments: [libraryId])
            )
            
            var processedFolderIds = Set<String>()
            var manualOrder = 0
            
            for folderJSON in metadata.folders {
                try processFolder(
                    db: db,
                    folderJSON: folderJSON,
                    libraryId: libraryId,
                    parentId: nil,
                    manualOrder: &manualOrder,
                    processedFolderIds: &processedFolderIds,
                    existingFolderIds: existingFolderIds
                )
            }
            
            let foldersToDelete = existingFolderIds.subtracting(processedFolderIds)
            for folderId in foldersToDelete {
                // Delete related records first
                _ = try db.execute(
                    sql: "DELETE FROM folderItem WHERE libraryId = ? AND folderId = ?",
                    arguments: [libraryId, folderId]
                )
                _ = try db.execute(
                    sql: "DELETE FROM folder WHERE libraryId = ? AND folderId = ?",
                    arguments: [libraryId, folderId]
                )
            }
            
            // Update the library's last imported modification time
            _ = try db.execute(
                sql: "UPDATE library SET lastImportedFolderMTime = ? WHERE id = ?",
                arguments: [metadata.modificationTime, libraryId]
            )
            
            Logger.app.debug("Metadata import completed")
        }
    }
    
    private func processFolder(
        db: Database,
        folderJSON: FolderJSON,
        libraryId: Int64,
        parentId: String?,
        manualOrder: inout Int,
        processedFolderIds: inout Set<String>,
        existingFolderIds: Set<String>
    ) throws {
        // Skip folders with missing or empty IDs
        guard let folderId = folderJSON.id, !folderId.isEmpty else {
            Logger.app.debug("Skipping folder with missing or empty ID")
            return
        }
        
        let name = folderJSON.name ?? ""
        var folder = Folder(
            libraryId: libraryId,
            folderId: folderId,
            parentId: parentId,
            name: name,
            nameForSort: nameForSort(from: name),
            modificationTime: folderJSON.modificationTime ?? 0,
            manualOrder: manualOrder
        )
        
        // Use save for existing folders, insert for new folders
        if existingFolderIds.contains(folderId) {
            // keep user setting fields: sortType and sortAscending
            try folder.update(db, columns: ["parentId", "name", "nameForSort", "modificationTime", "manualOrder"])
        } else {
            try folder.insert(db)
        }
        processedFolderIds.insert(folderId)
        manualOrder += 1
        
        // Process children if they exist
        if let children = folderJSON.children {
            for childJSON in children {
                try processFolder(
                    db: db,
                    folderJSON: childJSON,
                    libraryId: libraryId,
                    parentId: folderId,
                    manualOrder: &manualOrder,
                    processedFolderIds: &processedFolderIds,
                    existingFolderIds: existingFolderIds
                )
            }
        }
    }
    
    private func dataWithoutCache(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}

extension Array {
    func chunks(ofSize size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

//
//  MetadataImporter.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Foundation
import GoogleAPIClientForREST_Drive
import GRDB
import OSLog

struct MetadataImporter {
    enum Source {
        case url(url: URL)
        case gdrive(service: GTLRDriveService, fileId: String)
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
        let orderBy: String?
        let sortIncrease: Bool?
        let coverId: String?
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
        let tags: [String]?
        let annotation: String?
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
    
    let dbWriter: DatabaseWriter
    let libraryId: Int64
    let source: Source
    let localUrl: URL? // Optional URL to local storage for copying images (if useLocalStorage)
    let progressHandler: (Double) async -> Void // Callback to report import progress (0.0 to 1.0)
    
    var sourceRoot: SourceEntity {
        return createRootSourceEntity(source)
    }
    
    /// Import all data from Eagle library metadata (folders and items)
    func importAll() async throws {
        // Import folders first (assuming folders are 10% of the work)
        try await importFolders()
        
        await progressHandler(0.1) // 10% done after folders
        
        try Task.checkCancellation()
        
        // Import items (90% of the work)
        try await importItems(
            progressHandler: { itemProgress in
                // Convert item progress [0,1] to overall progress [0.1,1]
                await progressHandler(0.1 + 0.9 * itemProgress)
            }
        )
    }
    
    /// Import items from Eagle library metadata
    /// - Parameters:
    ///   - progressHandler: Callback to report import progress (0.0 to 1.0)
    func importItems(progressHandler: @escaping (Double) async -> Void) async throws {
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
            source: source,
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
                            let metadata = try await loadItemMetadata(itemId: itemId)
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
                let batchItems: [(item: StoredItem, metadata: ItemMetadataJSON)] = batchMetadata.map { itemId, metadata in
                    let item = buildItem(itemId: itemId, metadata: metadata)
                    return (item: item, metadata: metadata)
                }
                
                // Copy images to local storage if localUrl provided
                if localUrl != nil {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (item, _) in batchItems {
                            group.addTask {
                                try await copyItemImages(item: item)
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
    ///   - source: Eagle library source (url must be already activated, google service must be authorized)
    ///   - existingDbItemIds: Set of item IDs already in the database
    /// - Returns: Dictionary of all item IDs to their modification times
    ///           - New items (not in mtime.json or DB): assigned Int64.max to ensure import
    ///           - Items in DB but not in mtime.json: assigned 0 to preserve without re-import
    private func getAllItemTimes(
        source: Source,
        existingDbItemIds: Set<String>
    ) async throws -> [String: Int64] {
        let data = try await sourceRoot.appending("mtime.json", isFolder: false).getData()
        let mtimeData = try JSONDecoder().decode(MTimeJSON.self, from: data)
        
        // Only scan directory if counts don't match (indicating missing items)
        if mtimeData.totalCount != mtimeData.itemTimes.count {
            Logger.app.debug("Item count mismatch: total=\(mtimeData.totalCount), in mtime=\(mtimeData.itemTimes.count), scanning for missing items")
            return try await discoverAllItems(
                existingItemTimes: mtimeData.itemTimes,
                existingDbItemIds: existingDbItemIds
            )
        } else {
            return mtimeData.itemTimes
        }
    }
    
    /// Discover all item directories in the Eagle library and merge with existing mtime data
    /// - Parameters:
    ///   - existingItemTimes: Existing item modification times from mtime.json
    ///   - existingDbItemIds: Set of item IDs already in the database
    /// - Returns: Merged dictionary including all discovered items
    private func discoverAllItems(
        existingItemTimes: [String: Int64],
        existingDbItemIds: Set<String>
    ) async throws -> [String: Int64] {
        var allItemTimes = existingItemTimes
        
        guard let imagesDir = try? await sourceRoot.appending("images", isFolder: true) else {
            Logger.app.debug("Images directory does not exist")
            return allItemTimes
        }
        
        let contents = try await imagesDir.contentsOfFolder()
        var missingItemsNew: [String] = []
        var missingItemsInDb: [String] = []
        
        for (name, _) in contents {
            // Check if it's an .info directory
            if name.hasSuffix(".info") {
                // Extract item ID (remove .info suffix)
                let itemId = String(name.dropLast(5))
                
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
    
    private func loadItemMetadata(itemId: String) async throws -> ItemMetadataJSON {
        let data = try await sourceRoot.appending("images/\(itemId).info/metadata.json", isFolder: false).getData()
        return try JSONDecoder().decode(ItemMetadataJSON.self, from: data)
    }
    
    private func buildItem(
        itemId: String,
        metadata: ItemMetadataJSON
    ) -> StoredItem {
        let name = metadata.name ?? ""
        return StoredItem(
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
            duration: metadata.duration ?? 0,
            tags: metadata.tags ?? [],
            annotation: metadata.annotation ?? ""
        )
    }
    
    private func copyItemImages(item: StoredItem) async throws {
        guard let localUrl else {
            Logger.app.debug("library doesn't have local storage, skipping image copy")
            return
        }
        
        // Copy main image file
        let sourceImage = try await sourceRoot.appending(item.imagePath, isFolder: false)
        let destImagePath = localUrl.appending(path: item.imagePath, directoryHint: .notDirectory)
        
        // Create parent directory
        let destParent = destImagePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destParent, withIntermediateDirectories: true)
        
        // Remove existing file if it exists (to handle broken/changed files)
        if FileManager.default.fileExists(atPath: destImagePath.path) {
            try FileManager.default.removeItem(at: destImagePath)
        }
        
        // Copy image file
        try await sourceImage.copy(to: destImagePath)
        Logger.app.debug("Copied image: \(item.imagePath)")
        
        // Copy thumbnail if it exists and is different from main image
        if !item.noThumbnail {
            if let sourceThumbnail = try? await sourceRoot.appending(item.thumbnailPath, isFolder: false) {
                // ignore if thumbnail is not exist
                
                let destThumbnailPath = localUrl.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
                    
                // Remove existing thumbnail if it exists
                if FileManager.default.fileExists(atPath: destThumbnailPath.path) {
                    try FileManager.default.removeItem(at: destThumbnailPath)
                }
                    
                try await sourceThumbnail.copy(to: destThumbnailPath)
                Logger.app.debug("Copied thumbnail: \(item.thumbnailPath)")
            }
        }
    }
    
    private func processItem(
        db: Database,
        item: StoredItem,
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
    func importFolders() async throws {
        Logger.app.debug("Starting metadata import for library \(libraryId)")
        
        let data = try await sourceRoot.appending("metadata.json", isFolder: false).getData()
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

        // Map Eagle's orderBy to our FolderItemSortType
        let sortType: String
        if let orderBy = folderJSON.orderBy {
            switch orderBy {
            case "GLOBAL":
                sortType = FolderItemSortType.global.rawValue
            case "MANUAL":
                sortType = FolderItemSortType.manual.rawValue
            case "IMPORT":
                sortType = FolderItemSortType.dateAdded.rawValue
            case "NAME":
                sortType = FolderItemSortType.title.rawValue
            case "RATING":
                sortType = FolderItemSortType.rating.rawValue
            default:
                // Unsupported orderBy value, use default
                sortType = FolderItemSortOption.defaultValue.type.rawValue
            }
        } else {
            sortType = FolderItemSortOption.defaultValue.type.rawValue
        }

        let sortAscending = folderJSON.sortIncrease ?? FolderItemSortOption.defaultValue.ascending

        var folder = Folder(
            libraryId: libraryId,
            folderId: folderId,
            parentId: parentId,
            name: name,
            nameForSort: nameForSort(from: name),
            modificationTime: folderJSON.modificationTime ?? 0,
            manualOrder: manualOrder,
            coverItemId: folderJSON.coverId,
            sortType: sortType,
            sortAscending: sortAscending,
            sortModified: false // Only set to true when user changes in our app
        )

        // Use save for existing folders, insert for new folders
        if existingFolderIds.contains(folderId) {
            // keep user setting fields: sortType and sortAscending
            try folder.update(db, columns: ["parentId", "name", "nameForSort", "modificationTime", "manualOrder", "coverItemId"])

            // Update sort settings from Eagle metadata only if user hasn't modified them
            _ = try Folder
                .filter(Column("libraryId") == libraryId)
                .filter(Column("folderId") == folderId)
                .filter(Column("sortModified") == false)
                .updateAll(db, [
                    Column("sortType").set(to: sortType),
                    Column("sortAscending").set(to: sortAscending)
                ])
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
}

protocol SourceEntity {
    func appending(_ path: String, isFolder: Bool) async throws -> SourceEntity
    func getData() async throws -> Data
    func contentsOfFolder() async throws -> [(String, SourceEntity)]
    func copy(to destination: URL) async throws -> Void
}

struct NamedEntity {
    let name: String
    let entity: SourceEntity
}

func createRootSourceEntity(_ source: MetadataImporter.Source) -> any SourceEntity {
    switch source {
    case .url(let url):
        return URLSourceEntity(url: url)
    case .gdrive(let service, let fileId):
        return GoogleDriveSourceEntity(service: service, fileId: fileId)
    }
}

struct URLSourceEntity: SourceEntity {
    let url: URL
    
    func appending(_ path: String, isFolder: Bool) async throws -> SourceEntity {
        let newURL = url.appending(path: path, directoryHint: isFolder ? .isDirectory : .notDirectory)
        guard FileManager.default.fileExists(atPath: newURL.path) else {
            throw SourceEntityError.fileNotFound
        }
        return URLSourceEntity(url: newURL)
    }
    
    func getData() async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
    
    func contentsOfFolder() async throws -> [(String, SourceEntity)] {
        let paths = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return paths.map { path in
            (path.lastPathComponent, URLSourceEntity(url: path))
        }
    }
    
    func copy(to destination: URL) async throws {
        try FileManager.default.copyItem(at: url, to: destination)
    }
}

struct GoogleDriveSourceEntity: SourceEntity {
    let service: GTLRDriveService
    let fileId: String
    
    func appending(_ path: String, isFolder: Bool) async throws -> SourceEntity {
        var childFileId = fileId
        for name in path.split(separator: "/") {
            childFileId = try await GoogleDriveUtils.getChildFileId(
                service: service, folderId: childFileId, fileName: String(name)
            )
        }
        return GoogleDriveSourceEntity(service: service, fileId: childFileId)
    }
    
    func getData() async throws -> Data {
        return try await GoogleDriveUtils.getFileData(service: service, fileId: fileId)
    }
    
    func contentsOfFolder() async throws -> [(String, SourceEntity)] {
        let query = GTLRDriveQuery_FilesList.query()
        query.spaces = "drive"
        query.q = "'\(fileId)' in parents and trashed = false"
        query.fields = "files(id,name),nextPageToken"
        query.orderBy = "name"
        query.pageSize = 1000
        return try await withCheckedThrowingContinuation { cont in
            service.executeQuery(query) { _, result, error in
                if let error { return cont.resume(throwing: error) }
                guard let fileList = result as? GTLRDrive_FileList,
                      let files = fileList.files
                else {
                    return cont.resume(returning: [])
                }
                let entities = files.map { file in
                    (
                        file.name ?? "",
                        GoogleDriveSourceEntity(
                            service: service,
                            fileId: file.identifier ?? ""
                        )
                    )
                }
                cont.resume(returning: entities)
            }
        }
    }
    
    func copy(to destination: URL) async throws {
        let fetcher = service.fetcherService.fetcher(
            withURLString: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media"
        )
        fetcher.destinationFileURL = destination

        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { cont in
                    fetcher.beginFetch { _, error in
                        if let error = error {
                            try? FileManager.default.removeItem(at: destination)
                            cont.resume(throwing: error)
                            return
                        }
                        cont.resume(returning: ())
                    }
                }
            },
            onCancel: {
                fetcher.stopFetching()
                try? FileManager.default.removeItem(at: destination)
            }
        )
    }
}

enum SourceEntityError: Error {
    case fileNotFound
}

extension Array {
    func chunks(ofSize size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

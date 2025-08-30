//
//  LocalImageStorageManager.swift
//  EagleViewer
//
//  Created on 2025/08/27
//

import Foundation
import OSLog

class LocalImageStorageManager {
    static let shared = LocalImageStorageManager()
    
    private init() {}
    
    /// Get the local storage URL for a specific library
    /// Creates the directory structure if it doesn't exist
    /// - Parameter libraryId: The ID of the library
    /// - Returns: URL to the library's local storage directory
    /// - Throws: FileManager errors if directory creation fails
    func getLocalStorageURL(for libraryId: Int64) throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let localImagesURL = appSupportURL.appending(path: "LocalImages", directoryHint: .isDirectory)
        let libraryStorageURL = localImagesURL.appending(path: String(libraryId), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: libraryStorageURL, withIntermediateDirectories: true)
        return libraryStorageURL
    }
    
    /// Remove local storage for a specific library
    /// - Parameter libraryId: The ID of the library
    /// - Throws: FileManager errors if removal fails
    func removeLocalStorage(for libraryId: Int64) throws {
        let storageURL = try getLocalStorageURL(for: libraryId)
        if FileManager.default.fileExists(atPath: storageURL.path) {
            try FileManager.default.removeItem(at: storageURL)
            Logger.app.info("Removed local storage for library \(libraryId)")
        }
    }
    
    /// Check if local storage exists for a library
    /// - Parameter libraryId: The ID of the library
    /// - Returns: True if local storage directory exists
    func hasLocalStorage(for libraryId: Int64) -> Bool {
        do {
            let storageURL = try getLocalStorageURL(for: libraryId)
            return FileManager.default.fileExists(atPath: storageURL.path)
        } catch {
            return false
        }
    }
}
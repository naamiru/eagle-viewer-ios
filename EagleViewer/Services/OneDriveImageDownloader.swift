//
//  OneDriveImageDownloader.swift
//  EagleViewer
//
//  On-demand image downloader for OneDrive libraries.
//  Downloads images lazily when the UI needs them, instead of during import.
//

import Foundation
import OSLog

actor OneDriveImageDownloader {
    static let shared = OneDriveImageDownloader()

    /// Tracks in-flight downloads to deduplicate concurrent requests for the same path.
    private var inFlight: [String: Task<URL?, Error>] = [:]

    /// Downloads an image from OneDrive to local storage if it doesn't already exist.
    /// Returns the local file URL, or nil if download fails.
    ///
    /// - Parameters:
    ///   - rootItemId: The OneDrive item ID of the library root folder
    ///   - relativePath: The relative path within the library (e.g. "images/ABC.info/photo.jpg")
    ///   - localBaseURL: The local storage base URL (e.g. Application Support/LocalImages/{id}/)
    func ensureImageExists(
        rootItemId: String,
        relativePath: String,
        localBaseURL: URL
    ) async -> URL? {
        let localURL = localBaseURL.appending(path: relativePath, directoryHint: .notDirectory)

        // Already downloaded
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        // Check if already downloading
        if let existing = inFlight[relativePath] {
            return try? await existing.value
        }

        // Start download
        let task = Task<URL?, Error> {
            do {
                let sourceEntity = OneDriveSourceEntity(itemId: rootItemId)
                let fileEntity = try await sourceEntity.appending(relativePath, isFolder: false)
                try await fileEntity.copy(to: localURL)
                Logger.app.debug("OneDrive downloaded: \(relativePath)")
                return localURL
            } catch {
                Logger.app.warning("OneDrive download failed for \(relativePath): \(error)")
                return nil
            }
        }

        inFlight[relativePath] = task
        let result = try? await task.value

        // Clean up in-flight tracker
        inFlight.removeValue(forKey: relativePath)

        return result
    }
}

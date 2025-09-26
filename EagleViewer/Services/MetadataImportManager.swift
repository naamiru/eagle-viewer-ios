//
//  MetadataImportManager.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Foundation
import GRDB
import OSLog
import SwiftUI

class MetadataImportManager: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    
    private let metadataImporter = MetadataImporter()
    private var currentImportTask: Task<Void, Error>?
    
    func startImporting(
        library: Library,
        activeLibraryURL: URL?,
        dbWriter: DatabaseWriter,
        fullImport: Bool = false
    ) async {
        // Cancel any existing import task
        await MainActor.run {
            currentImportTask?.cancel()
        }
        
        // Start new import task
        let task = Task {
            // Set importing state to true and reset progress
            await MainActor.run {
                isImporting = true
                importProgress = 0.0
            }
            
            var libraryURL: URL?
            var localURL: URL?
            
            // Handle security-scoped resource for Eagle library access
            if library.useLocalStorage {
                // Get local storage URL for image copying
                localURL = try? LocalImageStorageManager.shared.getLocalStorageURL(for: library.id)
                
                // Temporarily access Eagle library for import
                guard case .file(let bookmarkData) = library.source else {
                    throw LibraryFolderError.accessDenied
                }

                var isStale = false
                libraryURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                guard let libraryURL, libraryURL.startAccessingSecurityScopedResource() else {
                    throw LibraryFolderError.accessDenied
                }
            } else {
                // Use the already-active library URL from LibraryFolderManager
                libraryURL = activeLibraryURL
            }
            
            // Ensure security-scoped resource is released when task ends
            defer {
                if localURL != nil, let libraryURL {
                    libraryURL.stopAccessingSecurityScopedResource()
                }
            }
            
            guard let libraryURL else {
                return
            }
            
            let importStatus: ImportStatus
            
            // Ensure importing state is reset and status is updated when task completes
            defer {
                Task {
                    // Update library import status first
                    do {
                        try await dbWriter.write { db in
                            try db.execute(
                                sql: "UPDATE library SET lastImportStatus = ? WHERE id = ?",
                                arguments: [importStatus.rawValue, library.id]
                            )
                        }
                    } catch {
                        Logger.app.warning("Failed to update import status: \(error)")
                    }
                    
                    // Then reset the importing state on main thread
                    await MainActor.run {
                        isImporting = false
                    }
                }
            }
            
            do {
                // Check for cancellation before importing
                try Task.checkCancellation()
                
                // For full import, reset the modification timestamps to force reimport of all data
                if fullImport {
                    try await dbWriter.write { db in
                        try db.execute(
                            sql: "UPDATE library SET lastImportedFolderMTime = 0, lastImportedItemMTime = 0 WHERE id = ?",
                            arguments: [library.id]
                        )
                    }
                }
                
                // Import all metadata (folders and items) with optional local storage
                try await metadataImporter.importAll(
                    dbWriter: dbWriter,
                    libraryId: library.id,
                    libraryUrl: libraryURL,
                    localUrl: localURL, // Pass local URL for image copying if useLocalStorage
                    progressHandler: { progress in
                        await MainActor.run {
                            self.importProgress = progress
                        }
                    }
                )
                
                importStatus = .success
            } catch {
                if error is CancellationError {
                    Logger.app.info("Import task was cancelled")
                    importStatus = .cancelled
                } else {
                    Logger.app.warning("Failed to import metadata: \(error)")
                    importStatus = .failed
                }
            }
        }
        
        await MainActor.run {
            currentImportTask = task
        }
    }
    
    @MainActor
    func cancelImporting() {
        currentImportTask?.cancel()
        currentImportTask = nil
    }
}

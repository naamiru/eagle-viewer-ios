//
//  MetadataImportManager.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Foundation
import GoogleAPIClientForREST_Drive
import GoogleSignIn
import GRDB
import OSLog
import SwiftUI

class MetadataImportManager: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    
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
            
            // reset the importing state on main thread
            defer {
                Task {
                    await MainActor.run {
                        isImporting = false
                    }
                }
            }
            
            let localURL: URL? = if library.useLocalStorage {
                try LocalImageStorageManager.shared.getLocalStorageURL(for: library.id)
            } else {
                nil
            }
            
            var source: MetadataImporter.Source?
            
            switch library.source {
            case .file(let bookmarkData):
                // Handle security-scoped resource for Eagle library access
                if library.useLocalStorage {
                    var isStale = false
                    let libraryURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: [],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    
                    guard libraryURL.startAccessingSecurityScopedResource() else {
                        throw LibraryFolderError.accessDenied
                    }
                    
                    source = .url(url: libraryURL)
                } else {
                    // Use the already-active library URL from LibraryFolderManager
                    guard let activeLibraryURL else {
                        return
                    }
                    source = .url(url: activeLibraryURL)
                }
            case .gdrive(let fileId):
                let user = try await GoogleAuthManager.ensureSignedIn()

                let service = GTLRDriveService()
                service.authorizer = user.fetcherAuthorizer
                service.shouldFetchNextPages = true

                source = .gdrive(service: service, fileId: fileId)
            case .onedrive(let itemId):
                // Verify user is signed in before starting import.
                // OneDriveSourceEntity handles token refresh internally via getValidAccessToken().
                _ = try await OneDriveAuthManager.ensureSignedIn()
                source = .onedrive(itemId: itemId)
            }
            
            // Ensure security-scoped resource is released when task of local library ends
            defer {
                if localURL != nil, case .url(let url) = source {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            guard let source else {
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
                let metadataImporter = MetadataImporter(
                    dbWriter: dbWriter,
                    libraryId: library.id,
                    source: source,
                    localUrl: localURL, // Pass local URL for image copying if useLocalStorage
                    progressHandler: { progress in
                        await MainActor.run {
                            self.importProgress = progress
                        }
                    }
                )
                try await metadataImporter.importAll()
                
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

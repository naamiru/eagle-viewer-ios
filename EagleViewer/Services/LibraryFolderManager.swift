//
//  LibraryFolderManager.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Combine
import Foundation
import OSLog

enum AccessState {
    case closed
    case opening
    case open
}

@MainActor
class LibraryFolderManager: ObservableObject {
    static let shared = LibraryFolderManager()
    
    @Published private(set) var accessState: AccessState = .closed
    @Published private(set) var activeLibraryURL: URL?
    @Published private(set) var currentLibraryURL: URL?

    private var currentBookmarkData: Data?
    
    // task for starting security scope resources
    // for cancellation
    //   - accessTask.cancel(): discard result without state modification
    //   - accessTaskCancelled = true: mark as closed
    // both cancellation methods cannot cancel immediately
    // (url.startAccessingSecurityScopedResource is not cancellable)
    private var accessTask: Task<URL, Error>?
    // manage accessTask cancel status
    private var accessTaskCancelled: Bool = false
    
    private let resourceHandler = SecurityScopedResourceHandler()
    
    private var isLocalLibrary: Bool {
        currentLibraryURL != nil && currentBookmarkData == nil
    }
    
    func updateCurrentLibrary(_ library: Library?) {
        // Handle nil library (no active library)
        guard let library = library else {
            discardAccess()
            return
        }
        
        if library.useLocalStorage {
            // Stop access to previous library if any
            discardAccess()

            // For local storage, set virtual URL without security-scoped access
            do {
                let localURL = try LocalImageStorageManager.shared.getLocalStorageURL(for: library.id)
                accessState = .open
                currentLibraryURL = localURL
                activeLibraryURL = localURL
                currentBookmarkData = nil // Not used for local storage
            } catch {
                Logger.app.error("Failed to get local storage URL: \(error)")
                accessState = .closed
            }
        } else {
            // Only handle .file source for now
            guard case .file(let bookmarkData) = library.source else {
                return
            }

            // Skip if same library bookmark
            if currentBookmarkData == bookmarkData {
                return
            }

            // Stop access to previous library if any
            discardAccess()

            // security-scoped access to Eagle library
            currentBookmarkData = bookmarkData
            startAccess()
        }
    }
    
    func stopAccess() {
        if accessTask != nil {
            accessTaskCancelled = true
        } else if let url = activeLibraryURL, !isLocalLibrary {
            url.stopAccessingSecurityScopedResource()
            accessState = .closed
            activeLibraryURL = nil
        }
    }
    
    private func discardAccess() {
        if let accessTask {
            accessTask.cancel()
        }
        
        if let url = activeLibraryURL, !isLocalLibrary {
            url.stopAccessingSecurityScopedResource()
        }
        
        accessState = .closed
        currentBookmarkData = nil
        currentLibraryURL = nil
        activeLibraryURL = nil
    }
    
    func resumeAccess() {
        if accessTask != nil {
            accessTaskCancelled = false
        } else if accessState == .closed, !isLocalLibrary {
            startAccess()
        }
    }
    
    private func startAccess() {
        Task {
            try? await getActiveLibraryURL()
        }
    }
    
    func getActiveLibraryURL() async throws -> URL {
        if let activeLibraryURL {
            return activeLibraryURL
        }
        
        if let accessTask {
            return try await accessTask.value
        }

        guard let bookmarkData = currentBookmarkData else {
            accessState = .closed
            throw LibraryFolderError.invalidBookmark
        }
        
        accessState = .opening
        
        let task = Task {
            do {
                let url = try await resourceHandler.start(bookmarkData: bookmarkData)
                if Task.isCancelled {
                    url.stopAccessingSecurityScopedResource()
                    throw CancellationError()
                }
                if accessTaskCancelled {
                    url.stopAccessingSecurityScopedResource()
                    throw LibraryFolderError.cancelled
                }
                accessState = .open
                currentLibraryURL = url
                activeLibraryURL = url
                return url
            } catch {
                if !(error is CancellationError) {
                    accessState = .closed
                    activeLibraryURL = nil
                }
                throw error
            }
        }
        accessTask = task
        defer {
            accessTask = nil
            accessTaskCancelled = false
        }
        
        return try await task.value
    }
}

actor SecurityScopedResourceHandler {
    func start(bookmarkData: Data) async throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmarkData,
                          options: [],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        
        if isStale {
            throw LibraryFolderError.bookmarkStale
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            throw LibraryFolderError.accessDenied
        }
        
        return url
    }
}

enum LibraryFolderError: LocalizedError {
    case invalidBookmark
    case accessDenied
    case bookmarkStale
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidBookmark:
            return "Failed to resolve library folder bookmark"
        case .accessDenied:
            return "Access denied to library folder"
        case .bookmarkStale:
            return "Library folder bookmark is stale and needs to be refreshed"
        case .cancelled:
            return "Folder access is cancelled"
        }
    }
}

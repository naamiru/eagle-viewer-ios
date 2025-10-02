//
//  CloudFile.swift
//  EagleViewer
//
//  Created on 2025/10/02
//

import Foundation

enum CloudFileError: Error, LocalizedError {
    case notFound(URL)
    case isDirectory(URL)
    case notFile(URL)
    case timedOut(URL)
    case coordinationFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notFound(let url): return "Item not found: \(url.path)"
        case .isDirectory(let url): return "Expected a file but found a directory: \(url.path)"
        case .notFile(let url): return "Expected a regular file: \(url.path)"
        case .timedOut(let url): return "Download timed out: \(url.path)"
        case .coordinationFailed(_, let underlying): return "File coordination failed: \(underlying.localizedDescription)"
        }
    }
}

enum CloudFile {
    // MARK: - Public API

    /// Check existence without forcing a download.
    /// - Returns true if:
    ///   - The item exists locally (placeholder or materialized), or
    ///   - The item is an iCloud item (ubiquitous) even if it's not yet downloaded.
    /// - Never starts a download.
    static func fileExists(at url: URL) async -> Bool {
        // 1) Cheap local check (includes placeholders/materialized)
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }

        // 2) Try a coordinated read to nudge placeholder creation (no download).
        //    If we get "no such file" error, we can safely return false.
        do {
            try await coordinateRead(at: url) { _ in }
        } catch {
            // If the coordination explicitly says "file not found", return false.
            if let nsErr = error as NSError?,
               nsErr.domain == NSCocoaErrorDomain,
               nsErr.code == NSFileNoSuchFileError || nsErr.code == NSFileReadNoSuchFileError
            {
                return false
            }
            // Otherwise, fall through and try metadata-based inference below.
        }

        // 3) Re-check local after coordination (a placeholder may now exist).
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }

        // 4) As a final inference, check ubiquitous metadata.
        //    If the URL is known to be an iCloud item, treat as "exists" even if not local.
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                          .ubiquitousItemDownloadingStatusKey]),
            values.isUbiquitousItem == true
        {
            return true
        }

        return false
    }

    /// Read file contents as Data.
    /// - Fast path: if the item is local (non-ubiquitous) or already materialized, return immediately.
    /// - Slow path: for iCloud non-current items, wait for download to complete (with timeout).
    static func fileData(at url: URL, timeout: TimeInterval = 300) async throws -> Data {
        // Reject directories early
        if try isDirectory(url) {
            throw CloudFileError.isDirectory(url)
        }

        // ---- Fast path: non-ubiquitous or already materialized iCloud ----
        let (isUbiq, isCurrent) = (try? ubiquitousQuickState(url)) ?? (false, false)
        if !isUbiq || isCurrent {
            if let reg = try? isRegularFile(url), reg == false {
                throw CloudFileError.notFile(url)
            }
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }

        // ---- Slow path: iCloud item not yet current ----
        // Coordinate a read to ensure placeholder exists (does not force download).
        try await coordinateRead(at: url) { _ in }

        // Start and wait for download to become current.
        try await ensureMaterializedIfNeeded(at: url, timeout: timeout)

        // Final validation and read
        guard try isRegularFile(url) else { throw CloudFileError.notFile(url) }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    /// Ensure that a file is fully materialized (downloaded) if it is an iCloud item.
    /// - Behavior:
    ///   - If the URL points to a local file, nothing is done.
    ///   - If the URL points to an iCloud file that is already materialized (.current), nothing is done.
    ///   - If the URL points to an iCloud file that is not yet materialized:
    ///       1. Perform a coordinated read to encourage placeholder creation.
    ///       2. Call `ensureMaterializedIfNeeded` to start downloading and wait until it's ready or timeout.
    /// - This function is intended to be called before operations that require local access,
    ///   such as copying the file or reading its Data contents.
    static func ensureMaterialized(at url: URL, timeout: TimeInterval = 300) async throws {
        // Quick probe
        let (isUbiq, isCurrent) = (try? ubiquitousQuickState(url)) ?? (false, false)

        // If not an iCloud item or already materialized -> nothing to do
        guard isUbiq, !isCurrent else { return }

        // For iCloud non-current items:
        // Step 1: coordinate a read to help create placeholder if missing
        try await coordinateRead(at: url) { _ in }

        // Step 2: wait until the item is materialized (downloaded)
        _ = try await ensureMaterializedIfNeeded(at: url, timeout: timeout)
    }

    // MARK: - Internals

    /// Ensure iCloud item is downloaded (materialized). Times out if it takes too long.
    /// Safe to call multiple times; no-ops for non-ubiquitous or already current items.
    @discardableResult
    private static func ensureMaterializedIfNeeded(at url: URL, timeout: TimeInterval) async throws -> Bool {
        let (isUbiq, isCurrent) = try ubiquitousQuickState(url)
        guard isUbiq, !isCurrent else { return false }

        // Start download if not already in progress.
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Poll until status becomes .current or timeout.
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            let (_, nowCurrent) = try ubiquitousQuickState(url)
            if nowCurrent { return true }
        }
        throw CloudFileError.timedOut(url)
    }

    /// Perform a coordinated read; useful to create/refresh placeholders without forcing a download.
    private static func coordinateRead(at url: URL, block: @escaping (URL) -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { newURL in
                block(newURL)
            }
            if let err = coordinationError {
                cont.resume(throwing: CloudFileError.coordinationFailed(url, underlying: err))
            } else {
                cont.resume(returning: ())
            }
        }
    }

    /// Minimal iOS-compatible ubiquitous state probe.
    /// - isUbiquitous: true if the item lives in iCloud Drive
    /// - isCurrent: true if the item is already downloaded/materialized locally
    private static func ubiquitousQuickState(_ url: URL) throws -> (isUbiquitous: Bool, isCurrent: Bool) {
        // remove cache
        var u = url
        u.removeAllCachedResourceValues()

        let values = try u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        let isUbiq = values.isUbiquitousItem ?? false
        let isCurrent = (values.ubiquitousItemDownloadingStatus == .current)
        return (isUbiq, isCurrent)
    }

    /// Return whether the URL is a directory (placeholder or materialized)
    private static func isDirectory(_ url: URL) throws -> Bool {
        let vals = try url.resourceValues(forKeys: [.isDirectoryKey])
        return vals.isDirectory ?? false
    }

    /// Return whether the URL is a regular file (placeholder or materialized)
    private static func isRegularFile(_ url: URL) throws -> Bool {
        let vals = try url.resourceValues(forKeys: [.isRegularFileKey])
        return vals.isRegularFile ?? false
    }
}

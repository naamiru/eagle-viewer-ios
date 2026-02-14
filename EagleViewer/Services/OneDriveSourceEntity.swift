//
//  OneDriveSourceEntity.swift
//  EagleViewer
//
//  Created on 2025/10/01
//

import Foundation
import OSLog

// MARK: - Concurrency Limiter

/// Controls concurrent OneDrive API requests to avoid 429 rate limiting.
actor OneDriveRequestLimiter {
    static let shared = OneDriveRequestLimiter()

    private let maxConcurrent = 2
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Minimum interval between releasing one request and starting another.
    private let minIntervalNs: UInt64 = 200_000_000  // 200ms
    private var lastReleaseTime: ContinuousClock.Instant = .now

    func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        lastReleaseTime = .now
        if let next = waiters.first {
            waiters.removeFirst()
            // Delay resuming to space out requests
            Task {
                try? await Task.sleep(nanoseconds: minIntervalNs)
                next.resume()
            }
        } else {
            activeCount -= 1
        }
    }
}

// MARK: - Child Item ID Cache

/// Caches resolved OneDrive item IDs to avoid redundant API calls.
/// Key use: the "images" folder under each library root is resolved once per import.
actor OneDriveItemIDCache {
    static let shared = OneDriveItemIDCache()

    // Cache key: "parentId/childName" → childItemId
    private var cache: [String: String] = [:]

    func get(parentId: String, childName: String) -> String? {
        cache["\(parentId)/\(childName)"]
    }

    func set(parentId: String, childName: String, childId: String) {
        cache["\(parentId)/\(childName)"] = childId
    }
}

// MARK: - Source Entity

struct OneDriveSourceEntity: SourceEntity {
    let itemId: String

    private static let graphBaseURL = "https://graph.microsoft.com/v1.0"
    private static let maxRetries = 5
    private static let initialBackoffSeconds: Double = 2.0

    func appending(_ path: String, isFolder: Bool) async throws -> SourceEntity {
        var currentId = itemId
        for name in path.split(separator: "/") {
            let childName = String(name)

            // Check cache first
            if let cachedId = await OneDriveItemIDCache.shared.get(parentId: currentId, childName: childName) {
                currentId = cachedId
                continue
            }

            let resolvedId = try await getChildItemId(parentId: currentId, childName: childName)

            // Cache the resolved ID
            await OneDriveItemIDCache.shared.set(parentId: currentId, childName: childName, childId: resolvedId)
            currentId = resolvedId
        }
        return OneDriveSourceEntity(itemId: currentId)
    }

    func getData() async throws -> Data {
        let url = URL(string: "\(Self.graphBaseURL)/me/drive/items/\(itemId)/content")!
        return try await performRequestWithRetry(url: url, label: "getData(\(itemId))") { token in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validateResponse(response, label: "getData(\(self.itemId))")
            return data
        }
    }

    func contentsOfFolder() async throws -> [(String, SourceEntity)] {
        var allItems: [(String, SourceEntity)] = []
        var nextURL: URL? = URL(string: "\(Self.graphBaseURL)/me/drive/items/\(itemId)/children?$select=id,name&$top=200")

        while let url = nextURL {
            let result: DriveChildrenResponse = try await performRequestWithRetry(url: url, label: "contentsOfFolder(\(itemId))") { token in
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Self.validateResponse(response, label: "contentsOfFolder(\(self.itemId))")
                return try JSONDecoder().decode(DriveChildrenResponse.self, from: data)
            }

            let items = result.value.map { child in
                (
                    child.name,
                    OneDriveSourceEntity(itemId: child.id) as SourceEntity
                )
            }
            allItems.append(contentsOf: items)

            if let next = result.nextLink {
                nextURL = URL(string: next)
            } else {
                nextURL = nil
            }
        }

        return allItems
    }

    func copy(to destination: URL) async throws {
        let url = URL(string: "\(Self.graphBaseURL)/me/drive/items/\(itemId)/content")!
        try await performRequestWithRetry(url: url, label: "copy(\(itemId))") { (token: String) -> Void in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (tempURL, response) = try await URLSession.shared.download(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                try? FileManager.default.removeItem(at: tempURL)
                let code = httpResponse.statusCode
                Logger.app.warning("OneDrive copy(\(self.itemId)) failed: HTTP \(code)")
                throw OneDriveAPIError.httpError(statusCode: code)
            }

            // Ensure destination directory exists
            let destDir = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
        }
    }

    // MARK: - Helpers

    private func getChildItemId(parentId: String, childName: String) async throws -> String {
        guard let encodedName = childName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw SourceEntityError.fileNotFound
        }

        let url = URL(string: "\(Self.graphBaseURL)/me/drive/items/\(parentId):/\(encodedName)")!
        return try await performRequestWithRetry(url: url, label: "getChildItemId(\(childName))") { token in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validateResponse(response, label: "getChildItemId(\(childName))")
            let item = try JSONDecoder().decode(DriveItem.self, from: data)
            return item.id
        }
    }

    // MARK: - Retry & Auth

    /// Executes a request with automatic token refresh, retry, and concurrency limiting.
    private func performRequestWithRetry<T>(
        url: URL,
        label: String,
        operation: @escaping (String) async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<Self.maxRetries {
            // Wait for concurrency slot
            await OneDriveRequestLimiter.shared.acquire()

            do {
                let token = try await OneDriveAuthManager.getValidAccessToken()
                let result = try await operation(token)
                await OneDriveRequestLimiter.shared.release()
                return result
            } catch let error as OneDriveAPIError where error.isRetryable {
                await OneDriveRequestLimiter.shared.release()
                lastError = error
                let delay = Self.initialBackoffSeconds * pow(2.0, Double(attempt))
                Logger.app.warning("OneDrive \(label) attempt \(attempt + 1) failed (retryable): \(error.localizedDescription), retrying in \(delay)s")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch let error as URLError where Self.isRetryableURLError(error) {
                await OneDriveRequestLimiter.shared.release()
                lastError = error
                let delay = Self.initialBackoffSeconds * pow(2.0, Double(attempt))
                Logger.app.warning("OneDrive \(label) attempt \(attempt + 1) network error: \(error.localizedDescription), retrying in \(delay)s")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                await OneDriveRequestLimiter.shared.release()
                // Non-retryable error — fail immediately
                throw error
            }
        }

        Logger.app.error("OneDrive \(label) failed after \(Self.maxRetries) attempts")
        throw lastError ?? SourceEntityError.fileNotFound
    }

    private static func validateResponse(_ response: URLResponse, label: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        let code = httpResponse.statusCode
        guard code == 200 else {
            Logger.app.warning("OneDrive \(label) HTTP \(code)")
            throw OneDriveAPIError.httpError(statusCode: code)
        }
    }

    private static func isRetryableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Error Types

enum OneDriveAPIError: LocalizedError {
    case httpError(statusCode: Int)

    var isRetryable: Bool {
        switch self {
        case .httpError(let code):
            // 401 = token expired (will refresh on retry)
            // 429 = rate limited
            // 500+ = server errors
            return code == 401 || code == 429 || code >= 500
        }
    }

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            switch code {
            case 401: return "Authentication expired"
            case 403: return "Access denied"
            case 404: return "File not found"
            case 429: return "Rate limited by OneDrive"
            default: return "OneDrive API error (HTTP \(code))"
            }
        }
    }
}

// MARK: - Graph API Response Models

private struct DriveChildrenResponse: Decodable {
    let value: [DriveChildItem]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

private struct DriveChildItem: Decodable {
    let id: String
    let name: String
}

private struct DriveItem: Decodable {
    let id: String
}

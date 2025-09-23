//
//  CacheManager.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import Combine
import Foundation

actor CacheManager {
    static let shared = CacheManager()

    enum Entry<T: Codable>: Codable {
        case stale(T)
        case fresh(T)
    }

    private var cachedValues: [String: Data] = [:]
    private var inProgressTasks: [String: Task<Data, Error>] = [:]
    private var keysExpiredDuringFetch: Set<String> = []

    private nonisolated let eventSubscription: AnyCancellable

    private init() {
        eventSubscription = EventCenter.shared.publisher.sink { event in
            Task {
                await CacheManager.shared.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: AppEvent) async {
        switch event {
        case .libraryWillChange:
            expireAll()
        case .globalSortChanged, .importProgressChanged:
            markAsStale(prefix: Self.folderCoverImageCacheKeyPrefix, type: CoverImageState.self)
            await MainActor.run {
                EventCenter.shared.post(.folderCacheInvalidated)
            }
        case .folderSortChanged(let folder):
            markAsStale(key: folderCoverImageCacheKey(folderId: folder.folderId), type: CoverImageState.self)
            await MainActor.run {
                EventCenter.shared.post(.folderCacheInvalidated)
            }
        default:
            break
        }
    }

    // MARK: primitive methods

    private func expire(key: String) {
        cachedValues.removeValue(forKey: key)
        if inProgressTasks[key] != nil {
            keysExpiredDuringFetch.insert(key)
        }
    }

    private func expire(prefix: String) {
        let keysToExpire = cachedValues.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToExpire {
            expire(key: key)
        }
    }

    private func expireAll() {
        cachedValues.removeAll()
        for key in inProgressTasks.keys {
            keysExpiredDuringFetch.insert(key)
        }
    }

    private func markAsStale<T: Codable>(key: String, type: T.Type) {
        markAsStale(keys: [key], type: T.self)
    }

    private func markAsStale<T: Codable>(prefix: String, type: T.Type) {
        let keysToMark = cachedValues.keys.filter { $0.hasPrefix(prefix) }
        markAsStale(keys: Array(keysToMark), type: T.self)
    }

    private func markAsStale<T: Codable>(keys: [String], type: T.Type) {
        guard !keys.isEmpty else { return }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        for key in keys {
            guard let cachedData = cachedValues[key] else { continue }

            do {
                if let entry = try? decoder.decode(Entry<T>.self, from: cachedData) {
                    switch entry {
                    case .fresh(let state):
                        let staleEntry = Entry<T>.stale(state)
                        cachedValues[key] = try encoder.encode(staleEntry)
                    case .stale:
                        // Already stale, no change needed
                        break
                    }
                }
            } catch {
                // If we can't decode/encode, just remove the entry
                cachedValues.removeValue(forKey: key)
            }
        }
    }

    private func findOrCreate<T: Codable>(
        key: String,
        createValue: @escaping () async throws -> T
    ) async throws -> Entry<T> {
        let decoder = JSONDecoder()

        // return from cache if exists and is fresh
        if let cachedData = cachedValues[key] {
            do {
                let entry = try decoder.decode(Entry<T>.self, from: cachedData)
                switch entry {
                case .fresh:
                    return entry // Return fresh entry as-is
                case .stale:
                    // Continue to refresh stale entry
                    break
                }
            } catch {
                cachedValues.removeValue(forKey: key)
            }
        }

        // check task in progress
        if let task = inProgressTasks[key] {
            let data = try await task.value
            return try decoder.decode(Entry<T>.self, from: data)
        }

        // create new task
        let task = Task<Data, Error> {
            let value = try await createValue()
            let freshEntry = Entry.fresh(value)
            let encoder = JSONEncoder()
            return try encoder.encode(freshEntry)
        }
        inProgressTasks[key] = task
        defer {
            inProgressTasks.removeValue(forKey: key)
        }

        // get data of new value
        let data = try await task.value

        // save to cache if not expired
        defer {
            keysExpiredDuringFetch.remove(key)
        }
        if !keysExpiredDuringFetch.contains(key) {
            cachedValues[key] = data
        }

        return try decoder.decode(Entry<T>.self, from: data)
    }

    func find<T: Codable>(key: String) -> Entry<T>? {
        if let cachedData = cachedValues[key] {
            do {
                let entry = try JSONDecoder().decode(Entry<T>.self, from: cachedData)
                return entry
            } catch {}
        }
        return nil
    }

    // MARK: Folder cover item cache

    enum CoverImageState: Codable {
        case empty // no cover image
        case url(URL)
    }

    private static let folderCoverImageCacheKeyPrefix = "folderCoverItem/"

    private func folderCoverImageCacheKey(folderId: String) -> String {
        Self.folderCoverImageCacheKeyPrefix + folderId
    }

    func findFolderCoverImage(folderId: String) -> Entry<CoverImageState>? {
        return find(key: folderCoverImageCacheKey(folderId: folderId))
    }

    func findOrCreateFolderCoverImage(
        folderId: String,
        getItem: @escaping () async throws -> CoverImageState
    ) async throws -> Entry<CoverImageState> {
        return try await findOrCreate(key: folderCoverImageCacheKey(folderId: folderId)) {
            try await getItem()
        }
    }
}

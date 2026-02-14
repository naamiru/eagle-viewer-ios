//
//  OneDriveSourceEntity.swift
//  EagleViewer
//
//  Created on 2025/10/01
//

import Foundation

struct OneDriveSourceEntity: SourceEntity {
    let accessToken: String
    let itemId: String

    private static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    func appending(_ path: String, isFolder: Bool) async throws -> SourceEntity {
        var currentId = itemId
        for name in path.split(separator: "/") {
            currentId = try await getChildItemId(parentId: currentId, childName: String(name))
        }
        return OneDriveSourceEntity(accessToken: accessToken, itemId: currentId)
    }

    func getData() async throws -> Data {
        // GET /me/drive/items/{itemId}/content returns 302 redirect to download URL
        let url = URL(string: "\(Self.graphBaseURL)/me/drive/items/\(itemId)/content")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SourceEntityError.fileNotFound
        }

        return data
    }

    func contentsOfFolder() async throws -> [(String, SourceEntity)] {
        var allItems: [(String, SourceEntity)] = []
        var nextURL: URL? = URL(string: "\(Self.graphBaseURL)/me/drive/items/\(itemId)/children?$select=id,name&$top=200")

        while let url = nextURL {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw SourceEntityError.fileNotFound
            }

            let result = try JSONDecoder().decode(DriveChildrenResponse.self, from: data)

            let items = result.value.map { child in
                (
                    child.name,
                    OneDriveSourceEntity(accessToken: accessToken, itemId: child.id) as SourceEntity
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
        // Download file content directly to destination URL
        let url = URL(string: "\(Self.graphBaseURL)/me/drive/items/\(itemId)/content")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (tempURL, response) = try await URLSession.shared.download(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            try? FileManager.default.removeItem(at: tempURL)
            throw SourceEntityError.fileNotFound
        }

        // Move downloaded file to destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    // MARK: - Helpers

    private func getChildItemId(parentId: String, childName: String) async throws -> String {
        // URL-encode the child name for the path
        guard let encodedName = childName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw SourceEntityError.fileNotFound
        }

        let url = URL(string: "\(Self.graphBaseURL)/me/drive/items/\(parentId):/\(encodedName)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SourceEntityError.fileNotFound
        }

        let item = try JSONDecoder().decode(DriveItem.self, from: data)
        return item.id
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

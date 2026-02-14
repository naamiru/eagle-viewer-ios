//
//  OneDriveFolderPickerView.swift
//  EagleViewer
//
//  Created on 2025/10/01
//

import SwiftUI

// MARK: - Model

struct OneDriveItem: Identifiable, Hashable {
    let id: String
    let name: String
    let isFolder: Bool
    let modifiedTime: Date?
}

// MARK: - OneDrive Client

final class OneDriveClient {
    private let accessToken: String
    private static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    func listChildren(of itemId: String) async throws -> [OneDriveItem] {
        let urlString: String
        if itemId == "root" {
            urlString = "\(Self.graphBaseURL)/me/drive/root/children?$select=id,name,folder,lastModifiedDateTime&$top=200&$orderby=name"
        } else {
            urlString = "\(Self.graphBaseURL)/me/drive/items/\(itemId)/children?$select=id,name,folder,lastModifiedDateTime&$top=200&$orderby=name"
        }

        var allItems: [OneDriveItem] = []
        var nextURL: URL? = URL(string: urlString)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        while let url = nextURL {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw NSError(domain: "OneDrive", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to list folder contents (HTTP \(httpResponse.statusCode))"
                ])
            }

            let result = try JSONDecoder().decode(ListChildrenResponse.self, from: data)

            let items = result.value.map { child in
                OneDriveItem(
                    id: child.id,
                    name: child.name,
                    isFolder: child.folder != nil,
                    modifiedTime: child.lastModifiedDateTime.flatMap { dateFormatter.date(from: $0) }
                )
            }
            allItems.append(contentsOf: items)

            if let next = result.nextLink {
                nextURL = URL(string: next)
            } else {
                nextURL = nil
            }
        }

        // Sort: folders first, then by name
        return allItems.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder && !$1.isFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Response Models

private struct ListChildrenResponse: Decodable {
    let value: [ListChildrenItem]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

private struct ListChildrenItem: Decodable {
    let id: String
    let name: String
    let folder: FolderFacet?
    let lastModifiedDateTime: String?
}

private struct FolderFacet: Decodable {
    let childCount: Int?
}

// MARK: - SwiftUI View

struct OneDriveFolderPickerView: View {
    let onSelect: (String, String) -> Void // Returns (libraryName, itemId)
    @State private var client: OneDriveClient
    @State private var path: [OneDriveItem] = []

    private let rootFolder = OneDriveItem(id: "root", name: String(localized: "OneDrive"), isFolder: true, modifiedTime: nil)

    init(accessToken: String, onSelect: @escaping (String, String) -> Void) {
        self.onSelect = onSelect
        _client = State(initialValue: OneDriveClient(accessToken: accessToken))
    }

    var body: some View {
        NavigationStack(path: $path) {
            OneDriveFolderContentView(client: client, folder: rootFolder, onSelect: onSelect)
                .navigationDestination(for: OneDriveItem.self) { folder in
                    OneDriveFolderContentView(
                        client: client,
                        folder: folder,
                        onSelect: onSelect
                    )
                }
        }
    }
}

// MARK: - Subview: Folder content

private struct OneDriveFolderContentView: View {
    let client: OneDriveClient
    let folder: OneDriveItem
    let onSelect: (String, String) -> Void

    @State private var isLoading = false
    @State private var entries: [OneDriveItem] = []
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                VStack(spacing: 6) {
                    ProgressView()
                    Text("LOADING")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let errorMessage, entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage).multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            } else if entries.isEmpty {
                VStack {
                    Text("No Items")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(entries) { item in
                        if item.isFolder {
                            NavigationLink(value: item) {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(item.name)
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                        if let modifiedTime = item.modifiedTime {
                                            Text(modifiedTime.smartString())
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "document")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(.tertiary)
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                    if let modifiedTime = item.modifiedTime {
                                        Text(modifiedTime.smartString())
                                            .font(.footnote)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.inset)
        .toolbar {
            ToolbarItem(id: "open-toolbar-item", placement: .topBarTrailing) {
                Button("Open", role: canSelect ? .confirm : nil) {
                    var libraryName = folder.name
                    if libraryName.hasSuffix(".library") {
                        libraryName = String(libraryName.dropLast(".library".count))
                    }
                    onSelect(libraryName, folder.id)
                    dismiss()
                }
                .disabled(!canSelect)
            }
        }
        .task { await load() }
    }

    private var canSelect: Bool {
        folder.name.hasSuffix(".library")
    }

    private func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        do {
            let list = try await client.listChildren(of: folder.id)
            await MainActor.run {
                self.entries = list
            }
        } catch {
            await MainActor.run {
                self.errorMessage = (error as NSError).localizedDescription
                self.entries = []
            }
        }
        await MainActor.run { self.isLoading = false }
    }
}

//
//  DriveFolderPickerView.swift
//  EagleViewer
//
//  Created on 2025/09/27
//

import GoogleAPIClientForREST_Drive
import GoogleSignIn
import SwiftUI

// MARK: - Model

struct GoogleDriveItem: Identifiable, Hashable {
    static let folderMimeType = "application/vnd.google-apps.folder"
    static let shortcutMimeType = "application/vnd.google-apps.shortcut"

    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: Date?
    var isFolder: Bool { mimeType == Self.folderMimeType }
}

// MARK: - Drive Client (My Drive only)

final class GoogleDriveClient {
    private let service = GTLRDriveService()

    init(googleUser: GIDGoogleUser) {
        service.authorizer = googleUser.fetcherAuthorizer
        service.shouldFetchNextPages = true
    }

    /// Returns the list of children under a given folder in "My Drive".
    /// - The result is sorted so that folders appear first, then files.
    /// - Google Drive shortcuts are automatically resolved to their targets.
    func listChildren(of folderId: String) async throws -> [GoogleDriveItem] {
        let query = GTLRDriveQuery_FilesList.query()
        query.spaces = "drive" // My Drive only
        query.q = "'\(folderId)' in parents and trashed = false"
        query.fields = "files(id,name,mimeType,shortcutDetails,modifiedTime),nextPageToken"
        query.orderBy = "folder,name"
        query.pageSize = 1000

        return try await withCheckedThrowingContinuation { cont in
            service.executeQuery(query) { _, result, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let fileList = result as? GTLRDrive_FileList,
                      let files = fileList.files
                else {
                    cont.resume(returning: [])
                    return
                }
                // Resolve shortcuts to their targets
                let items: [GoogleDriveItem] = files.compactMap { f in
                    var id = f.identifier ?? ""
                    var mime = f.mimeType ?? ""
                    if mime == GoogleDriveItem.shortcutMimeType,
                       let targetId = f.shortcutDetails?.targetId,
                       let targetMime = f.shortcutDetails?.targetMimeType
                    {
                        id = targetId
                        mime = targetMime
                        // keep the shortcut’s name
                    }
                    return GoogleDriveItem(
                        id: id,
                        name: f.name ?? "",
                        mimeType: mime,
                        modifiedTime: f.modifiedTime?.date
                    )
                }
                // Ensure folders first, then files, both sorted by name
                let sorted = items.sorted {
                    if $0.isFolder != $1.isFolder { return $0.isFolder && !$1.isFolder }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                cont.resume(returning: sorted)
            }
        }
    }
}

// MARK: - SwiftUI View

struct GoogleDriveFolderPickerView: View {
    let onSelect: (String, String) -> Void // Returns the (libraryName, folderId)
    @State private var client: GoogleDriveClient
    @State private var path: [GoogleDriveItem] = []

    private let rootFolder = GoogleDriveItem(id: "root", name: String(localized: "My Drive"), mimeType: GoogleDriveItem.folderMimeType, modifiedTime: nil)

    init(googleUser: GIDGoogleUser, onSelect: @escaping (String, String) -> Void) {
        self.onSelect = onSelect
        _client = State(initialValue: GoogleDriveClient(googleUser: googleUser))
    }

    var body: some View {
        NavigationStack(path: $path) {
            FolderContentView(client: client, folder: rootFolder, onSelect: onSelect)
                .navigationDestination(for: GoogleDriveItem.self) { folder in
                    FolderContentView(
                        client: client,
                        folder: folder,
                        onSelect: onSelect
                    )
                }
        }
    }
}

// MARK: - Subview: Folder content

private struct FolderContentView: View {
    let client: GoogleDriveClient
    let folder: GoogleDriveItem
    let onSelect: (String, String) -> Void

    @State private var isLoading = false
    @State private var entries: [GoogleDriveItem] = []
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

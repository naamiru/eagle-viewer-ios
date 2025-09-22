//
//  ItemInfoView.swift
//  EagleViewer
//
//  Created on 2025/09/22
//

import GRDB
import GRDBQuery
import SwiftUI

struct ItemInfoView: View {
    let item: Item
    @State private var storedItemRequest: StoredItemRequest
    @State private var itemFoldersRequest: ItemFoldersRequest

    @Environment(\.dismiss) private var dismiss

    init(item: Item) {
        self.item = item
        _storedItemRequest = State(initialValue: StoredItemRequest(id: item.id))
        _itemFoldersRequest = State(initialValue: ItemFoldersRequest(id: item.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ItemInfoInnerView(storedItemRequest: $storedItemRequest, itemFoldersRequest: $itemFoldersRequest)
                    .padding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Info")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

struct ItemInfoInnerView: View {
    @Query<StoredItemRequest> private var item: StoredItem
    @Query<ItemFoldersRequest> private var folders: [Folder]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var imageViewerManager: ImageViewerManager
    @EnvironmentObject private var navigationManager: NavigationManager
    @EnvironmentObject private var searchManager: SearchManager

    init(storedItemRequest: Binding<StoredItemRequest>, itemFoldersRequest: Binding<ItemFoldersRequest>) {
        _item = Query(storedItemRequest)
        _folders = Query(itemFoldersRequest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: item.name)
                    .bold()
                Text(verbatim: "\(item.ext.uppercased()) · \(item.width) × \(item.height) · \(sizeText(item.size))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if item.star > 0 {
                    HStack(spacing: 2) {
                        ForEach(0 ..< 5, id: \.self) { i in
                            Image(systemName: i < item.star ? "star.fill" : "star")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Folders")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                FlowLayout(alignment: .leading) {
                    if !folders.isEmpty {
                        ForEach(folders, id: \.folderId) { folder in
                            Button(action: {
                                moveToFolder(folder)
                            }) {
                                Text(verbatim: folder.name)
                                    .lineLimit(1)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 12)
                                    .foregroundColor(.primary.opacity(0.6))
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(.gray.opacity(0.4))
                                    )
                            }
                        }
                    } else {
                        Button(action: {
                            moveToUncategorized()
                        }) {
                            Text("Uncategorized")
                                .padding(.vertical, 5)
                                .padding(.horizontal, 12)
                                .foregroundColor(.primary.opacity(0.6))
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.gray.opacity(0.4))
                                )
                        }
                    }
                }
            }

            if !item.tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.secondary)
                    FlowLayout(alignment: .leading) {
                        ForEach(item.tags, id: \.self) { tag in
                            Button(action: {
                                moveToTag(tag)
                            }) {
                                Text(verbatim: tag)
                                    .lineLimit(1)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 12)
                                    .foregroundColor(.primary.opacity(0.6))
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(.gray.opacity(0.4))
                                    )
                            }
                        }
                    }
                }
            }

            if !item.annotation.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.secondary)
                    Text(verbatim: item.annotation)
                        .textSelection(.enabled)
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.6))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.gray.opacity(0.1))
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sizeText(_ sizeInBytes: Int) -> String {
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0

        let size = Double(sizeInBytes)

        if size >= gb {
            return String(format: "%.1fGB", size / gb)
        } else if size >= mb {
            return String(format: "%.1fMB", size / mb)
        } else if size >= kb {
            return String(format: "%.1fKB", size / kb)
        } else {
            return "\(sizeInBytes)B"
        }
    }

    private func moveToFolder(_ folder: Folder) {
        dismiss()
        imageViewerManager.hide()
        DispatchQueue.main.async {
            navigationManager.path = [.folder(folder.id)]
        }
    }

    private func moveToUncategorized() {
        dismiss()
        imageViewerManager.hide()
        DispatchQueue.main.async {
            navigationManager.path = [.uncategorized]
        }
    }

    private func moveToTag(_ tag: String) {
        dismiss()
        imageViewerManager.hide()
        DispatchQueue.main.async {
            if navigationManager.path == [.all] {
                searchManager.searchText = tag
            } else {
                searchManager.keepSearchTextInNextNavigation(searchText: tag)
                navigationManager.path = [.all]
            }
        }
    }
}

struct StoredItemRequest: ValueObservationQueryable {
    var id: Item.ID

    static var defaultValue: StoredItem {
        return StoredItem.empty
    }

    func fetch(_ db: Database) throws -> StoredItem {
        let item = try StoredItem
            .filter(Column("libraryId") == id.libraryId)
            .filter(Column("itemId") == id.itemId)
            .filter(Column("isDeleted") == false)
            .fetchOne(db)
        return item ?? StoredItem.empty
    }
}

struct ItemFoldersRequest: ValueObservationQueryable {
    var id: Item.ID

    static var defaultValue: [Folder] {
        return []
    }

    func fetch(_ db: Database) throws -> [Folder] {
        return try Folder
            .filter(Column("libraryId") == id.libraryId)
            .joining(required: Folder.folderItems.filter(Column("itemId") == id.itemId))
            .order(Column("manualOrder"))
            .fetchAll(db)
    }
}

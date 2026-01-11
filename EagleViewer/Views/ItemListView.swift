//
//  ItemListView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

struct ItemListView: View {
    let items: [Item]
    let placeholderType: PlaceholderType

    @EnvironmentObject var imageViewerManager: ImageViewerManager
    @EnvironmentObject private var searchManager: SearchManager

    init(items: [Item], placeholderType: PlaceholderType = .none) {
        self.items = items
        self.placeholderType = placeholderType
    }

    private func needShowType(item: Item) -> Bool {
        if ItemVideoView.isVideo(item: item) {
            return true
        }

        if item.isTextFile {
            return true
        }

        let ext = item.ext.lowercased()
        if ext == "webp" || ext == "gif" {
            return true
        }

        return false
    }

    var body: some View {
        if items.isEmpty && placeholderType != .none {
            switch placeholderType {
            case .search:
                NoResultsView()
            case .default:
                NoItemView()
            case .none:
                EmptyView()
            }
        } else {
            ScrollViewReader { proxy in
                AdaptiveGridView(isCollection: false) {
                    ForEach(items) { item in
                        ItemThumbnailView(item: item)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .contentShape(Rectangle())
                            .if(needShowType(item: item)) { view in
                                view.overlay(alignment: .topLeading) {
                                    Text(item.ext.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        .padding(5)
                                        .allowsHitTesting(false)
                                }
                            }
                            .id(item.itemId)
                            .onTapGesture {
                                searchManager.hideSearch()
                                imageViewerManager.show(item: item, items: items, onDismiss: { selectedItem in
                                    if item != selectedItem {
                                        proxy.scrollTo(selectedItem.itemId, anchor: .center)
                                    }
                                })
                            }
                    }
                }
                .onChange(of: searchManager.scrollToTopTrigger) {
                    if let firstItem = items.first {
                        proxy.scrollTo(firstItem.itemId, anchor: .top)
                    }
                }
            }
        }
    }
}

struct ItemListRequestView<T: ValueObservationQueryable>: View where T.Value == [Item], T.Context == DatabaseContext {
    @Query<T> var items: [Item]
    let placeholderType: PlaceholderType

    init(request: Binding<T>, placeholderType: PlaceholderType = .none) {
        _items = Query(request, in: \.databaseContext)
        self.placeholderType = placeholderType
    }

    var body: some View {
        ItemListView(items: items, placeholderType: placeholderType)
    }
}

struct NoItemView: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("No Images")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 200)
    }
}

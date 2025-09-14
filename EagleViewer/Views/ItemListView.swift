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

    @State private var selectedItem: Item?
    @State private var scrollToItem: Item?

    init(items: [Item], placeholderType: PlaceholderType = .none) {
        self.items = items
        self.placeholderType = placeholderType
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
                            .id(item.itemId)
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                }
                .fullScreenCover(item: $selectedItem) { item in
                    if ItemVideoView.isVideo(item: item) {
                        ItemVideoView(item: item)
                    } else {
                        ImageDetailView(
                            item: item,
                            items: items.filter { !ItemVideoView.isVideo(item: $0) },
                            dismiss: { item in
                                if item != selectedItem {
                                    scrollToItem = item
                                }
                                selectedItem = nil
                            }
                        )
                    }
                }
                .onChange(of: scrollToItem) {
                    if let item = scrollToItem {
                        proxy.scrollTo(item.itemId, anchor: .center)
                        scrollToItem = nil
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

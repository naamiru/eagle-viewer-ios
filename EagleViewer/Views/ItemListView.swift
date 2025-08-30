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
    @State private var selectedItem: Item?
    let showPlaceholder: Bool

    init(items: [Item], showPlaceholder: Bool = false) {
        self.items = items
        self.showPlaceholder = showPlaceholder
    }

    var body: some View {
        if items.isEmpty && showPlaceholder {
            NoItemView()
        } else {
            AdaptiveGridView(isCollection: false) {
                ForEach(items) { item in
                    ItemThumbnailView(item: item)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .contentShape(Rectangle())
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
                        items: items.filter { !ItemVideoView.isVideo(item: $0) }
                    )
                }
            }
        }
    }
}

struct ItemListRequestView<T: ValueObservationQueryable>: View where T.Value == [Item], T.Context == DatabaseContext {
    @Query<T> var items: [Item]
    let showPlaceholder: Bool

    init(request: Binding<T>, showPlaceholder: Bool = false) {
        _items = Query(request, in: \.databaseContext)
        self.showPlaceholder = showPlaceholder
    }

    var body: some View {
        ItemListView(items: items, showPlaceholder: showPlaceholder)
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

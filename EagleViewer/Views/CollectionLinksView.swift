//
//  CollectionLinksView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

struct CollectionLinksView: View {
    @State private var allCoverItemRequest = AllCoverItemRequest(libraryId: 0, sortOption: .defaultValue)
    @State private var uncategorizedCoverItemRequest = UncategorizedCoverItemRequest(libraryId: 0, sortOption: .defaultValue)

    @Environment(\.library) private var library
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        CollectionLinksInnerView(
            allCoverItemRequest: $allCoverItemRequest,
            uncategorizedCoverItemRequest: $uncategorizedCoverItemRequest
        )
        .onChange(of: library.id, initial: true) {
            allCoverItemRequest.libraryId = library.id
            uncategorizedCoverItemRequest.libraryId = library.id
        }
        .onChange(of: settingsManager.globalSortOption, initial: true) {
            allCoverItemRequest.sortOption = settingsManager.globalSortOption
            uncategorizedCoverItemRequest.sortOption = settingsManager.globalSortOption
        }
    }
}

struct CollectionLinksInnerView: View {
    @Query<AllCoverItemRequest> private var allCoverItem: Item?
    @Query<UncategorizedCoverItemRequest> private var uncategorizedCoverItem: Item?
    @EnvironmentObject private var settingsManager: SettingsManager

    init(
        allCoverItemRequest: Binding<AllCoverItemRequest>,
        uncategorizedCoverItemRequest: Binding<UncategorizedCoverItemRequest>
    ) {
        _allCoverItem = Query(allCoverItemRequest)
        _uncategorizedCoverItem = Query(uncategorizedCoverItemRequest)
    }

    var body: some View {
        AdaptiveGridView(isCollection: true) {
            NavigationLink(value: NavigationDestination.all) {
                CollectionItemThumbnailView(title: "All", item: allCoverItem)
            }
            .buttonStyle(PlainButtonStyle())

            if let uncategorizedCoverItem {
                NavigationLink(value: NavigationDestination.uncategorized) {
                    CollectionItemThumbnailView(title: "Uncategorized", item: uncategorizedCoverItem)
                }
                .buttonStyle(PlainButtonStyle())
            }

            NavigationLink(value: NavigationDestination.random) {
                CollectionThumbnailView(title: "Random", noGradation: true) {
                    Color.gray.opacity(0.4)
                        .overlay(
                            VStack {
                                Spacer()
                                Image(systemName: "shuffle")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

struct AllCoverItemRequest: ValueObservationQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption

    static var defaultValue: Item? { nil }

    func fetch(_ db: Database) throws -> Item? {
        try ItemQuery.allItems(libraryId: libraryId, sortOption: sortOption)
            .fetchOne(db)
    }
}

struct UncategorizedCoverItemRequest: ValueObservationQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption

    static var defaultValue: Item? { nil }

    func fetch(_ db: Database) throws -> Item? {
        try ItemQuery.uncategorizedItems(libraryId: libraryId, sortOption: sortOption)
            .fetchOne(db)
    }
}

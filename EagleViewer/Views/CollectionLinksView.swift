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
    @Query(AllCoverItemRequest(libraryId: 0, sortOption: .defaultValue)) private var allCoverItem: Item?
    @Query(UncategorizedCoverItemRequest(libraryId: 0, sortOption: .defaultValue)) private var uncategorizedCoverItem: Item?

    @Environment(\.library) private var library
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        AdaptiveGridView(isCollection: true) {
            NavigationLink(value: NavigationDestination.all) {
                CollectionItemThumbnailView(title: String(localized: "All"), item: allCoverItem)
            }
            .buttonStyle(PlainButtonStyle())

            if let uncategorizedCoverItem {
                NavigationLink(value: NavigationDestination.uncategorized) {
                    CollectionItemThumbnailView(title: String(localized: "Uncategorized"), item: uncategorizedCoverItem)
                }
                .buttonStyle(PlainButtonStyle())
            }

            NavigationLink(value: NavigationDestination.random) {
                CollectionThumbnailView(title: String(localized: "Random"), noGradation: true) {
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
        .onChange(of: library.id, initial: true) {
            $allCoverItem.libraryId.wrappedValue = library.id
            $uncategorizedCoverItem.libraryId.wrappedValue = library.id
        }
        .onChange(of: settingsManager.globalSortOption, initial: true) {
            $allCoverItem.sortOption.wrappedValue = settingsManager.globalSortOption
            $uncategorizedCoverItem.sortOption.wrappedValue = settingsManager.globalSortOption
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

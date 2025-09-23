//
//  CollectionView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import GRDB
import GRDBQuery
import SwiftUI

struct AllCollectionView: View {
    var body: some View {
        CollectionView<AllCollectionRequest>(title: String(localized: "All"), navigationDestination: .all)
    }
}

struct UncategorizedCollectionView: View {
    var body: some View {
        CollectionView<UncategorizedCollectionRequest>(title: String(localized: "Uncategorized"), navigationDestination: .uncategorized)
    }
}

struct RandomCollectionView: View {
    var body: some View {
        CollectionView<RandomCollectionRequest>(title: String(localized: "Random"), navigationDestination: .random)
    }
}

struct CollectionView<T: CollectionQueryable>: View where T.Value == [Item], T.Context == DatabaseContext {
    let title: String
    let navigationDestination: NavigationDestination

    @State private var request: T

    @Environment(\.library) private var library
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var navigationManager: NavigationManager
    @EnvironmentObject private var searchManager: SearchManager

    init(title: String, navigationDestination: NavigationDestination) {
        self.title = title
        self.navigationDestination = navigationDestination
        _request = State(initialValue: T(libraryId: 0, sortOption: .defaultValue, searchText: ""))
    }

    var body: some View {
        ScrollView {
            ItemListRequestView(request: $request, placeholderType: searchManager.debouncedSearchText.isEmpty ? .default : .search)
        }
        .ignoresSafeArea(edges: .horizontal)
        .searchDismissible()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: library.id, initial: true) {
            request.libraryId = library.id
        }
        .onChange(of: settingsManager.globalSortOption, initial: true) {
            request.sortOption = settingsManager.globalSortOption
        }
        .onAppear {
            searchManager.setSearchHandler(initialSearchText: request.searchText) { text in
                request.searchText = text
            }
        }
        .safeAreaPadding(.bottom, 52)
    }
}

protocol CollectionQueryable: ValueObservationQueryable {
    var libraryId: Int64 { get set }
    var sortOption: GlobalSortOption { get set }
    var searchText: String { get set }
    init(libraryId: Int64, sortOption: GlobalSortOption, searchText: String)
}

struct AllCollectionRequest: CollectionQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption
    var searchText: String = ""

    static var defaultValue: [Item] { [] }

    func fetch(_ db: Database) throws -> [Item] {
        try ItemQuery.allItems(libraryId: libraryId, sortOption: sortOption, searchText: searchText)
            .fetchAll(db)
    }
}

struct UncategorizedCollectionRequest: CollectionQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption
    var searchText: String = ""

    static var defaultValue: [Item] { [] }

    func fetch(_ db: Database) throws -> [Item] {
        try ItemQuery.uncategorizedItems(libraryId: libraryId, sortOption: sortOption, searchText: searchText)
            .fetchAll(db)
    }
}

struct RandomCollectionRequest: CollectionQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption
    var searchText: String = ""

    static var defaultValue: [Item] { [] }

    func fetch(_ db: Database) throws -> [Item] {
        try ItemQuery.randomItems(libraryId: libraryId, searchText: searchText)
            .fetchAll(db)
    }
}

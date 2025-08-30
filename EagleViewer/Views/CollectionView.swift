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
        CollectionView<AllCollectionRequest>(title: "All", navigationDestination: .all)
    }
}

struct UncategorizedCollectionView: View {
    var body: some View {
        CollectionView<UncategorizedCollectionRequest>(title: "Uncategorized", navigationDestination: .uncategorized)
    }
}

struct RandomCollectionView: View {
    var body: some View {
        CollectionView<RandomCollectionRequest>(title: "Random", navigationDestination: .random)
    }
}

struct CollectionView<T: CollectionQueryable>: View where T.Value == [Item], T.Context == DatabaseContext {
    let title: String
    let navigationDestination: NavigationDestination

    @State private var request: T

    @Environment(\.library) private var library
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var navigationManager: NavigationManager

    init(title: String, navigationDestination: NavigationDestination) {
        self.title = title
        self.navigationDestination = navigationDestination
        _request = State(initialValue: T(libraryId: 0, sortOption: .defaultValue))
    }

    var body: some View {
        ScrollView {
            ItemListRequestView(request: $request, showPlaceholder: true)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: library.id, initial: true) {
            request.libraryId = library.id
        }
        .onChange(of: settingsManager.globalSortOption, initial: true) {
            request.sortOption = settingsManager.globalSortOption
        }
    }
}

protocol CollectionQueryable: ValueObservationQueryable {
    var libraryId: Int64 { get set }
    var sortOption: GlobalSortOption { get set }
    init(libraryId: Int64, sortOption: GlobalSortOption)
}

struct AllCollectionRequest: CollectionQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption

    static var defaultValue: [Item] { [] }

    func fetch(_ db: Database) throws -> [Item] {
        try CollectionQuery.allItems(libraryId: libraryId, sortOption: sortOption)
            .fetchAll(db)
    }
}

struct UncategorizedCollectionRequest: CollectionQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption

    static var defaultValue: [Item] { [] }

    func fetch(_ db: Database) throws -> [Item] {
        try CollectionQuery.uncategorizedItems(libraryId: libraryId, sortOption: sortOption)
            .fetchAll(db)
    }
}

struct RandomCollectionRequest: CollectionQueryable {
    var libraryId: Int64
    var sortOption: GlobalSortOption

    static var defaultValue: [Item] { [] }

    func fetch(_ db: Database) throws -> [Item] {
        try CollectionQuery.randomItems(libraryId: libraryId)
            .fetchAll(db)
    }
}

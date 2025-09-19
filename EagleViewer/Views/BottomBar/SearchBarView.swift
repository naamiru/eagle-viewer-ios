//
//  SearchBarView.swift
//  EagleViewer
//
//  Created on 2025/09/19
//

import GRDB
import GRDBQuery
import SwiftUI

struct SearchBarView: View {
    @EnvironmentObject private var searchManager: SearchManager
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack {
            SearchSuggestView()

            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search", text: $searchManager.searchText)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .focused($isSearchFieldFocused)
                        .submitLabel(.search)

                    if !searchManager.searchText.isEmpty {
                        Button(action: {
                            searchManager.clearSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .frame(height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 22))
                .glassEffect(.regular)

                Button(action: {
                    isSearchFieldFocused = false
                    searchManager.clearSearch()
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(Color.primary)
                }
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .glassEffect(.regular.interactive())
            }
        }
        .onAppear {
            isSearchFieldFocused = true
        }
        .onChange(of: isSearchFieldFocused) {
            if !isSearchFieldFocused {
                searchManager.hideSearch()
            }
        }
    }
}

struct SearchSuggestView: View {
    @State private var request = TagCountsRequest(libraryId: 0, destination: nil, searchText: "")

    @Environment(\.library) private var library
    @EnvironmentObject private var searchManager: SearchManager
    @EnvironmentObject private var navigationManager: NavigationManager

    var body: some View {
        SearchSuggestInnerView(tagCountsRequest: $request)
            .onChange(of: library.id, initial: true) {
                request.libraryId = library.id
            }
            .onChange(of: navigationManager.path.last, initial: true) {
                request.destination = navigationManager.path.last
            }
            .onChange(of: searchManager.debouncedSearchText, initial: true) {
                request.searchText = searchManager.debouncedSearchText
            }
    }
}

struct SearchSuggestInnerView: View {
    @Query<TagCountsRequest> private var tagCounts: [TagCount]

    @EnvironmentObject private var searchManager: SearchManager

    init(tagCountsRequest: Binding<TagCountsRequest>) {
        _tagCounts = Query(tagCountsRequest)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !tagCounts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(tagCounts.enumerated(), id: \.element.tag) { index, tagCount in
                        HStack {
                            Image(systemName: "tag")
                                .font(.caption)
                            Text(tagCount.tag)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 200)
                                .fixedSize()
                            Spacer()
                            Text(String(tagCount.count))
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                        }
                        .padding(.horizontal)
                        .if(index == 0) { view in view.padding(.top) }
                        .if(index != 0) { view in view.padding(.top, 6) }
                        .if(index == tagCounts.count - 1) { view in view.padding(.bottom) }
                        .if(index != tagCounts.count - 1) { view in view.padding(.bottom, 6) }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTagTapped(tag: tagCount.tag)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
    }

    private func onTagTapped(tag: String) {
        let replaced = if searchManager.searchText.firstRange(of: /\s/) != nil {
            searchManager.searchText.replacing(/(\s)\S*$/) { match in
                match.1 + tag
            }
        } else {
            tag
        }
        searchManager.searchText = replaced + " "
    }
}

struct TagCountsRequest: ValueObservationQueryable {
    var libraryId: Int64
    var destination: NavigationDestination?
    var searchText: String

    static let queryableOptions = QueryableOptions.async

    static var defaultValue: [TagCount] { [] }

    func fetch(_ db: Database) throws -> [TagCount] {
        let (itemSearchText, tagSearchText) = splitSearchText()
        if tagSearchText.isEmpty {
            return []
        }

        switch destination {
        case nil: // Home
            return []
        case .folder(let id):
            return try TagQuery.tagsInFolder(
                libraryId: libraryId,
                folderId: id.folderId,
                itemSearchText: itemSearchText,
                tagSearchText: tagSearchText,
                limit: 4
            ).fetchAll(db)
        case .all, .random:
            return try TagQuery.tagsInAll(
                libraryId: libraryId,
                itemSearchText: itemSearchText,
                tagSearchText: tagSearchText,
                limit: 4
            ).fetchAll(db)
        case .uncategorized:
            return try TagQuery.tagsInUncategorized(
                libraryId: libraryId,
                itemSearchText: itemSearchText,
                tagSearchText: tagSearchText,
                limit: 4
            ).fetchAll(db)
        }
    }

    private func splitSearchText() -> (String, String) {
        guard let lastSpaceIndex = searchText.lastIndex(where: { $0.isWhitespace }) else {
            return ("", searchText)
        }

        return (
            String(searchText[..<lastSpaceIndex]).trimmingCharacters(in: .whitespacesAndNewlines),
            String(searchText[searchText.index(after: lastSpaceIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

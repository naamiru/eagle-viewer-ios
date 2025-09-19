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
    @State private var tagCountsequest = TagCountsRequest(libraryId: 0, destination: nil, searchText: "")
    @State private var searchHistoriesRequest = SearchHistoriesRequest(libraryId: 0, searchHistoryType: .folder)

    @Environment(\.library) private var library
    @EnvironmentObject private var searchManager: SearchManager
    @EnvironmentObject private var navigationManager: NavigationManager

    var body: some View {
        SearchSuggestInnerView(
            tagCountsRequest: $tagCountsequest,
            searchHistoriesRequest: $searchHistoriesRequest
        )
        .onChange(of: library.id, initial: true) {
            tagCountsequest.libraryId = library.id
            searchHistoriesRequest.libraryId = library.id
        }
        .onChange(of: navigationManager.path.last, initial: true) {
            tagCountsequest.destination = navigationManager.path.last
            searchHistoriesRequest.searchHistoryType = navigationManager.path.isEmpty ? .folder : .item
        }
        .onChange(of: searchManager.debouncedSearchText, initial: true) {
            tagCountsequest.searchText = searchManager.debouncedSearchText
        }
    }
}

struct SearchSuggestInnerView: View {
    @Query<TagCountsRequest> private var tagCounts: [TagCount]
    @Query<SearchHistoriesRequest> private var searchHistories: [SearchHistory]

    @EnvironmentObject private var searchManager: SearchManager
    @Environment(\.repositories) private var repositories

    init(tagCountsRequest: Binding<TagCountsRequest>, searchHistoriesRequest: Binding<SearchHistoriesRequest>) {
        _tagCounts = Query(tagCountsRequest)
        _searchHistories = Query(searchHistoriesRequest)
    }

    var body: some View {
        HStack(spacing: 0) {
            if searchManager.searchText.isEmpty {
                if !searchHistories.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(searchHistories.enumerated(), id: \.element.searchText) { index, searchHistory in
                            HStack {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text(searchHistory.searchText)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 200)
                                    .fixedSize()
                                Spacer()
                                Button(action: {
                                    Task {
                                        try? await repositories.searchHistory.deleteSearchHistory(searchHistory)
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(Color.secondary.opacity(0.5))
                                }
                                .padding(.leading, 12)
                            }
                            .padding(.horizontal)
                            .if(index == 0) { view in view.padding(.top) }
                            .if(index != 0) { view in view.padding(.top, 6) }
                            .if(index == searchHistories.count - 1) { view in view.padding(.bottom) }
                            .if(index != searchHistories.count - 1) { view in view.padding(.bottom, 6) }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSearchHistorySelected(searchHistory: searchHistory)
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                if !tagCounts.isEmpty {
                    VStack(spacing: 0) {
                        let (_, searched) = TagCountsRequest.splitSearchText(searchManager.debouncedSearchText)
                        ForEach(tagCounts.enumerated(), id: \.element.tag) { index, tagCount in
                            HStack {
                                Image(systemName: "tag")
                                    .font(.caption)
                                Text(highlightString(str: tagCount.tag, searched: searched))
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
                                onTagSelected(tag: tagCount.tag)
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Spacer()
        }
    }

    private func onTagSelected(tag: String) {
        let replaced = if searchManager.searchText.firstRange(of: /\s/) != nil {
            searchManager.searchText.replacing(/(\s)\S*$/) { match in
                match.1 + tag
            }
        } else {
            tag
        }
        searchManager.searchText = replaced + " "
    }

    private func onSearchHistorySelected(searchHistory: SearchHistory) {
        searchManager.searchText = searchHistory.searchText
        searchManager.hideSearch()
    }

    private func deleteSearchHistories(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let searchHistory = searchHistories[index]
                try? await repositories.searchHistory.deleteSearchHistory(searchHistory)
            }
        }
    }

    private func highlightString(str: String, searched: String) -> AttributedString {
        func normalString(_ str: Substring) -> AttributedString {
            var attrStr = AttributedString(str)
            attrStr.foregroundColor = .secondary
            return attrStr
        }

        func highlightedString(_ str: Substring) -> AttributedString {
            return AttributedString(str)
        }

        var remainingString = str[...]
        var result = AttributedString()

        while let range = remainingString.range(of: searched, options: .caseInsensitive) {
            result += normalString(remainingString[..<range.lowerBound])
            result += highlightedString(remainingString[range])
            remainingString = remainingString[range.upperBound...]
        }

        result += normalString(remainingString)
        return result
    }
}

struct TagCountsRequest: ValueObservationQueryable {
    var libraryId: Int64
    var destination: NavigationDestination?
    var searchText: String

    static let queryableOptions = QueryableOptions.async

    static var defaultValue: [TagCount] { [] }

    func fetch(_ db: Database) throws -> [TagCount] {
        let (itemSearchText, tagSearchText) = TagCountsRequest.splitSearchText(searchText)
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

    static func splitSearchText(_ searchText: String) -> (String, String) {
        guard let lastSpaceIndex = searchText.lastIndex(where: { $0.isWhitespace }) else {
            return ("", searchText)
        }

        return (
            String(searchText[..<lastSpaceIndex]).trimmingCharacters(in: .whitespacesAndNewlines),
            String(searchText[searchText.index(after: lastSpaceIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct SearchHistoriesRequest: ValueObservationQueryable {
    var libraryId: Int64
    var searchHistoryType: SearchHistoryType

    static let queryableOptions = QueryableOptions.async

    static var defaultValue: [SearchHistory] { [] }

    func fetch(_ db: Database) throws -> [SearchHistory] {
        return try SearchHistory
            .filter(Column("libraryId") == libraryId)
            .filter(Column("searchHistoryType") == searchHistoryType.rawValue)
            .order(Column("searchedAt").desc)
            .limit(4)
            .fetchAll(db)
    }
}

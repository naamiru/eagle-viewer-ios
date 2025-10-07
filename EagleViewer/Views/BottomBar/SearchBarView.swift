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
                .regularGlassEffect(interactive: false)

                Button(action: {
                    isSearchFieldFocused = false
                    DispatchQueue.main.async { // avoid conflict between list and keyboard animation
                        searchManager.clearSearch()
                    }
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(Color.primary)
                }
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .regularGlassEffect(interactive: true)
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
    @State private var searchHistoriesRequest = SearchHistoriesRequest(libraryId: 0, searchHistoryType: .folder, searchText: "")

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
            searchHistoriesRequest.searchText = searchManager.debouncedSearchText
        }
    }
}

struct SearchSuggestInnerView: View {
    @Query<TagCountsRequest> private var tagCounts: [TagCount]
    @Query<SearchHistoriesRequest> private var searchHistories: [SearchHistory]

    @EnvironmentObject private var searchManager: SearchManager
    @Environment(\.repositories) private var repositories

    let maxCount = 4

    init(tagCountsRequest: Binding<TagCountsRequest>, searchHistoriesRequest: Binding<SearchHistoriesRequest>) {
        _tagCounts = Query(tagCountsRequest)
        _searchHistories = Query(searchHistoriesRequest)
    }

    var filteredTagCounts: [TagCount] {
        let count = maxCount - searchHistories.count

        if count <= 0 {
            return []
        }

        let filtered = tagCounts.filter { tagCount in
            !searchHistories.contains { $0.searchText == tagCount.tag }
        }

        if filtered.count <= count {
            return filtered
        }

        return [TagCount](filtered[..<count])
    }

    var body: some View {
        HStack(spacing: 0) {
            let tagCounts = filteredTagCounts
            if !searchHistories.isEmpty || !tagCounts.isEmpty {
                VStack(spacing: 0) {
                    let (_, searched) = TagCountsRequest.splitSearchText(searchManager.searchText)

                    ForEach(Array(searchHistories.enumerated()), id: \.element.searchText) { index, searchHistory in
                        let isFirst = index == 0
                        let isLast = index == maxCount - 1 || (index == searchHistories.count - 1 && tagCounts.isEmpty)
                        HStack {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text(highlightString(str: searchHistory.searchText, searched: searched))
                                .lineLimit(1)
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
                        .if(isFirst) { view in view.padding(.top) }
                        .if(!isFirst) { view in view.padding(.top, 6) }
                        .if(isLast) { view in view.padding(.bottom) }
                        .if(!isLast) { view in view.padding(.bottom, 6) }
                        .frame(maxWidth: 250)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSearchHistorySelected(searchHistory: searchHistory)
                        }
                    }

                    ForEach(Array(tagCounts.enumerated()), id: \.element.tag) { index, tagCount in
                        let isFirst = index == 0 && searchHistories.isEmpty
                        let isLast = index == tagCounts.count - 1
                        HStack {
                            Image(systemName: "tag")
                                .font(.caption)
                            Text(highlightString(str: tagCount.tag, searched: searched))
                                .lineLimit(1)
                            Spacer()
                            Text(String(tagCount.count))
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                        }
                        .padding(.horizontal)
                        .if(isFirst) { view in view.padding(.top) }
                        .if(!isFirst) { view in view.padding(.top, 6) }
                        .if(isLast) { view in view.padding(.bottom) }
                        .if(!isLast) { view in view.padding(.bottom, 6) }
                        .frame(maxWidth: 250)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTagSelected(tag: tagCount.tag)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .glassBackground(in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
    }

    private func onTagSelected(tag: String) {
        searchManager.setSearchTextImmediately(
            combineSearchText(
                searchText: searchManager.searchText,
                tag: tag
            ) + " "
        )
    }

    private func onSearchHistorySelected(searchHistory: SearchHistory) {
        searchManager.setSearchTextImmediately(searchHistory.searchText + " ")
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

    /**
     * Combines a search text and a selected tag.
     *
     * It first trims leading and trailing whitespace from the search text.
     * Assuming suggestions are based on partial matches, it then finds the longest match
     * between the end of the search text and any part of the tag (case-insensitively) to combine them.
     *
     * - Parameters:
     * - searchText: The current text in the search field.
     * - tag: The tag selected by the user.
     * - Returns: The combined new search text.
     */
    func combineSearchText(searchText: String, tag: String) -> String {
        // 1. Trim leading and trailing whitespace (spaces, tabs, newlines, etc.) from the search text.
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. If the trimmed result is empty, return the tag directly.
        if trimmedSearchText.isEmpty {
            return tag
        }

        // 3. Loop from the beginning of the trimmed search text to find the longest possible match.
        for index in trimmedSearchText.indices {
            // 4. Check if the current position is at a word boundary (start of string or after whitespace).
            //    This improves performance by avoiding unnecessary 'contains' checks inside words.
            let isAtStart = (index == trimmedSearchText.startIndex)
            let isPrecededByWhitespace = !isAtStart && trimmedSearchText[trimmedSearchText.index(before: index)].isWhitespace

            if isAtStart || isPrecededByWhitespace {
                // 5. If it's a word boundary, get the substring from the current position to the end.
                let suffix = String(trimmedSearchText[index...])

                // 6. Perform a case-insensitive check to see if the tag contains the suffix.
                if tag.range(of: suffix, options: .caseInsensitive) != nil {
                    // The first match found is guaranteed to be the longest one because we are looping from the start.
                    let baseText = String(trimmedSearchText[..<index])
                    return baseText + tag
                }
            }
        }

        // 7. If no overlapping part is found, combine the trimmed search text and the tag with a space.
        return trimmedSearchText + " " + tag
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
    var searchText: String

    static let queryableOptions = QueryableOptions.async

    static var defaultValue: [SearchHistory] { [] }

    func fetch(_ db: Database) throws -> [SearchHistory] {
        var query = SearchHistory
            .filter(Column("libraryId") == libraryId)
            .filter(Column("searchHistoryType") == searchHistoryType.rawValue)

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearchText.isEmpty {
            let escapedSearchText = ItemQuery.escapeLike(trimmedSearchText)
            query = query.filter(Column("searchText").like("%\(escapedSearchText)%", escape: "\\"))

            query = query.filter(
                sql: "NOT (INSTR(LOWER(?), LOWER(searchText)) > 0)",
                arguments: [trimmedSearchText]
            )
        }
        return try query
            .order(Column("searchedAt").desc)
            .limit(4)
            .fetchAll(db)
    }
}

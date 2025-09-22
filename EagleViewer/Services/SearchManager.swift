//
//  SearchManager.swift
//  EagleViewer
//
//  Created on 2025/09/14
//

import Combine
import SwiftUI

class SearchManager: ObservableObject {
    @Published var searchText = ""
    @Published var debouncedSearchText = ""
    @Published var isSearchActive = false
    @Published var scrollToTopTrigger = UUID()

    private var currentPageHandler: ((String) -> Void)?
    private var isKeepingSearchTextInNextNavigation = false
    private var searchCancellable: AnyCancellable?

    init() {
        // Debounce search text changes
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] debouncedText in
                self?.debouncedSearchText = debouncedText
                self?.currentPageHandler?(debouncedText)
            }
    }

    func setSearchHandler(_ handler: @escaping (String) -> Void) {
        if isKeepingSearchTextInNextNavigation {
            isKeepingSearchTextInNextNavigation = false
            currentPageHandler = handler
            // Immediately call handler with existing search text
            handler(debouncedSearchText)
        } else {
            // Reset everything when page changes
            clearSearch()
            currentPageHandler = handler
        }
        isSearchActive = false
    }

    func showSearch() {
        withAnimation {
            isSearchActive = true
        }
    }

    func hideSearch() {
        isSearchActive = false
    }

    func clearSearch() {
        searchText = ""
        debouncedSearchText = ""
    }

    func keepSearchTextInNextNavigation(searchText: String) {
        self.searchText = searchText
        debouncedSearchText = searchText
        isKeepingSearchTextInNextNavigation = true
    }

    func setSearchTextImmediately(_ text: String) {
        searchText = text
        debouncedSearchText = text
        currentPageHandler?(text)
    }

    func triggerScrollToTop() {
        scrollToTopTrigger = UUID()
    }
}

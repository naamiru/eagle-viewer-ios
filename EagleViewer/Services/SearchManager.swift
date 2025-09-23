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

    func setSearchHandler(initialSearchText: String, handler: @escaping (String) -> Void) {
        currentPageHandler = nil

        if isKeepingSearchTextInNextNavigation {
            isKeepingSearchTextInNextNavigation = false
        } else {
            // Reset everything when page changes
            setSearchTextImmediately(initialSearchText)
        }

        // immediately apply search
        currentPageHandler = handler
        handler(debouncedSearchText)

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
        setSearchTextImmediately("")
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

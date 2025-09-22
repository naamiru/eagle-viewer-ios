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
        } else {
            // Reset everything when page changes
            clearSearch()
        }
        isSearchActive = false
        currentPageHandler = handler
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
}

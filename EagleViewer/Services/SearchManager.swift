//
//  SearchManager.swift
//  EagleViewer
//
//  Created on 2025/09/14
//

import SwiftUI

class SearchManager: ObservableObject {
    @Published var searchText = ""
    @Published var isSearchActive = false

    private var currentPageHandler: ((String) -> Void)?

    func setSearchHandler(_ handler: @escaping (String) -> Void) {
        // Reset everything when page changes
        clearSearch()
        isSearchActive = false
        currentPageHandler = handler
    }

    func showSearch() {
        isSearchActive = true
    }

    func hideSearch() {
        isSearchActive = false
        clearSearch()
    }

    func updateSearchText(_ text: String) {
        searchText = text
        currentPageHandler?(text)
    }

    func clearSearch() {
        searchText = ""
        currentPageHandler?("")
    }
}
//
//  SearchManager.swift
//  EagleViewer
//
//  Created on 2025/09/14
//

import SwiftUI
import Combine

class SearchManager: ObservableObject {
    @Published var searchText = ""
    @Published var debouncedSearchText = ""
    @Published var isSearchActive = false

    private var currentPageHandler: ((String) -> Void)?
    private var unfocusHandler: (() -> Void)?
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

    func clearSearch() {
        searchText = ""
        debouncedSearchText = ""
    }

    func setUnfocusHandler(_ handler: @escaping () -> Void) {
        unfocusHandler = handler
    }

    func unfocusSearch() {
        unfocusHandler?()
    }
}
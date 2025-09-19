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
            HStack {
                SearchSuggest()
                Spacer()
            }

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

struct SearchSuggest: View {
    @State private var request = UsedTagsRequest()

    @EnvironmentObject private var searchManager: SearchManager
    @EnvironmentObject private var navigationManager: NavigationManager

    var body: some View {
        VStack {
            Text("tag name 1")
            Text("tag name 2")
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct UsedTagsRequest: ValueObservationQueryable {
    static var defaultValue: [String] { [] }

    func fetch(_ db: Database) throws -> [String] {
        return []
    }
}

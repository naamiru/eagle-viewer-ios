//
//  SearchBottomBarView.swift
//  EagleViewer
//
//  Created on 2025/09/14
//

import SwiftUI

struct SearchBottomBarView: View {
    @EnvironmentObject private var searchManager: SearchManager
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
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
                searchManager.hideSearch()
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(Color.primary)
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
            .glassEffect(.regular.interactive())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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

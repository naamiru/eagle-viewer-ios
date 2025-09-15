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
            .padding(8)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)

            Button("Cancel") {
                isSearchFieldFocused = false
                searchManager.hideSearch()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground).ignoresSafeArea(edges: .horizontal))
        .overlay(
            Rectangle()
                .ignoresSafeArea(edges: .horizontal)
                .frame(height: 0.5)
                .foregroundColor(Color(UIColor.separator)),
            alignment: .top
        )
        .onAppear {
            isSearchFieldFocused = true
            searchManager.setUnfocusHandler {
                isSearchFieldFocused = false
            }
        }
    }
}

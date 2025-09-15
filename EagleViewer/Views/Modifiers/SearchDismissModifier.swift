//
//  SearchDismissModifier.swift
//  EagleViewer
//
//  Created on 2025/09/14
//

import SwiftUI

struct SearchDismissModifier: ViewModifier {
    @EnvironmentObject private var searchManager: SearchManager

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                if searchManager.isSearchActive {
                    searchManager.unfocusSearch()
                }
            }
            .simultaneousGesture(
                DragGesture()
                    .onChanged { _ in
                        if searchManager.isSearchActive {
                            searchManager.unfocusSearch()
                        }
                    }
            )
    }
}

extension View {
    func searchDismissible() -> some View {
        modifier(SearchDismissModifier())
    }
}
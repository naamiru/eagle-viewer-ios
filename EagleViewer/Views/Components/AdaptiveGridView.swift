//
//  AdaptiveGridView.swift
//  EagleViewer
//
//  Created on 2025/08/27
//

import SwiftUI

struct AdaptiveGridView<Content: View>: View {
    let isCollection: Bool
    @EnvironmentObject private var settingsManager: SettingsManager
    @Environment(\.isPortrait) private var isPortrait
    @ViewBuilder let content: () -> Content
    
    init(
        isCollection: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isCollection = isCollection
        self.content = content
    }
    
    private var spacing: CGFloat {
        if isCollection {
            switch settingsManager.layout {
            case .col3:
                return 10
            case .col4:
                return 8
            case .col6:
                return 6
            }
        } else {
            return 2
        }
    }
    
    private var horizontalPadding: CGFloat {
        isCollection ? 20 : 0
    }
    
    private var columnCount: Int {
        settingsManager.layout.columnCount(isPortrait: isPortrait)
    }
    
    var body: some View {
        LazyVGrid(
            columns: Array(repeating: .init(.flexible(), spacing: spacing), count: columnCount),
            alignment: .center,
            spacing: spacing
        ) {
            content()
        }
        .padding(.horizontal, horizontalPadding)
    }
}

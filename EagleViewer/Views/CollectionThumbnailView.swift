//
//  CollectionThumbnailView.swift
//  EagleViewer
//
//  Created on 2025/08/21
//

import SwiftUI

struct CollectionThumbnailView<Content: View>: View {
    let title: String
    let noGradation: Bool
    let showLabel: Bool
    let content: Content?

    @EnvironmentObject private var settingsManager: SettingsManager

    var cornerRadius: CGFloat {
        switch settingsManager.layout {
        case .col3:
            return 16
        case .col4:
            return 12
        case .col6:
            return 8
        }
    }

    init(title: String, noGradation: Bool = false, showLabel: Bool = true, @ViewBuilder content: () -> Content?) {
        self.title = title
        self.noGradation = noGradation
        self.showLabel = showLabel
        self.content = content()
    }

    var body: some View {
        Group {
            if let content = content {
                content
            } else {
                Color.gray.opacity(0.4)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .if(showLabel) { view in
            view.overlay(
                VStack {
                    Spacer()
                    Text(title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .if(!noGradation && content != nil) { view in
                            view.background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.clear, .black.opacity(0.4)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// Convenience initializer for when no content is provided
extension CollectionThumbnailView where Content == EmptyView {
    init(title: String, showLabel: Bool = true) {
        self.title = title
        self.noGradation = true
        self.showLabel = showLabel
        self.content = nil
    }
}

struct CollectionItemThumbnailView: View {
    let title: String
    let item: Item?
    let showLabel: Bool
    @State private var isPlaceholder: Bool = true

    init(title: String, item: Item?, showLabel: Bool = true) {
        self.title = title
        self.item = item
        self.showLabel = showLabel
    }

    var body: some View {
        if let item {
            CollectionThumbnailView(title: title, noGradation: isPlaceholder, showLabel: showLabel) {
                ItemThumbnailView(item: item, isPlaceholder: $isPlaceholder)
            }
        } else {
            CollectionThumbnailView(title: title, showLabel: showLabel)
        }
    }
}

struct CollectionURLThumbnailView: View {
    let title: String
    let url: URL
    let showLabel: Bool
    @State private var isPlaceholder: Bool = true

    init(title: String, url: URL, showLabel: Bool = true) {
        self.title = title
        self.url = url
        self.showLabel = showLabel
    }

    var body: some View {
        CollectionThumbnailView(title: title, noGradation: isPlaceholder, showLabel: showLabel) {
            ThumbnailView(url: url, isPlaceholder: $isPlaceholder)
        }
    }
}

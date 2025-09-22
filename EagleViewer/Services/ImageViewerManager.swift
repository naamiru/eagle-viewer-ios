//
//  ImageViewerManager.swift
//  EagleViewer
//
//  Created on 2025/09/18
//

import SwiftUI

class ImageViewerManager: ObservableObject {
    @Published var isPresented = false

    var item: Item?
    var items: [Item]?
    var dismiss: ((Item) -> Void)?

    func show(item: Item, items: [Item], onDismiss: @escaping (Item) -> Void) {
        self.item = item
        self.items = items
        dismiss = { value in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isPresented = false
            }
            onDismiss(value)
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            self.isPresented = true
        }
    }

    func hide() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

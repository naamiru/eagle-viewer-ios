//
//  ImageDetailView.swift
//  EagleViewer
//
//  Created on 2025/08/20
//

import CoreGraphics
import Nuke
import SwiftUI

struct ImageDetailView: View {
    @State var selectedItem: Item
    let items: [Item]

    @State private var isNoUI = false
    @State private var swipeDisabled = false

    @Environment(\.dismiss) private var dismiss

    private let prefetcher = ImagePrefetcher()
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager

    init(item: Item, items: [Item]) {
        selectedItem = item
        self.items = items
    }

    private var selectedItemId: Binding<String?> {
        Binding(
            get: { selectedItem.itemId },
            set: { newId in
                if let newId = newId, let item = items.first(where: { $0.itemId == newId }) {
                    selectedItem = item
                    prefetchAdjacentImages(for: item)
                }
            }
        )
    }

    private func getImageURL(for item: Item) -> URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    private func prefetchAdjacentImages(for item: Item) {
        guard let currentIndex = items.firstIndex(where: { $0.itemId == item.itemId }) else {
            return
        }

        var urlsToPrefetch: [URL] = []

        if currentIndex > 0 {
            let prevItem = items[currentIndex - 1]
            if let prevURL = getImageURL(for: prevItem) {
                urlsToPrefetch.append(prevURL)
            }
        }

        if currentIndex < items.count - 1 {
            let nextItem = items[currentIndex + 1]
            if let nextURL = getImageURL(for: nextItem) {
                urlsToPrefetch.append(nextURL)
            }
        }

        if !urlsToPrefetch.isEmpty {
            let requests = urlsToPrefetch.map { ImageRequest(url: $0) }
            prefetcher.startPrefetching(with: requests)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                ZStack {
                    isNoUI ? Color.black : Color.white

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(items, id: \.itemId) { item in
                                ItemImageViewer(
                                    item: item,
                                    size: geometry.size,
                                    isNoUI: $isNoUI,
                                    swipeDisabled: $swipeDisabled
                                )
                                .id(item.itemId)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollDisabled(swipeDisabled)
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: selectedItemId)
                }
                .ignoresSafeArea()
                .navigationTitle(selectedItem.name)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(isNoUI)
                .statusBar(hidden: isNoUI)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "chevron.down")
                        }
                        .opacity(isNoUI ? 0 : 1)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            prefetchAdjacentImages(for: selectedItem)
        }
        .onDisappear {
            prefetcher.stopPrefetching()
        }
    }
}

struct ItemImageViewer: View {
    let item: Item
    let size: CGSize
    @Binding var isNoUI: Bool
    @Binding var swipeDisabled: Bool

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            let frame = getImageFrame()
            ItemImageView(item: item)
                .frame(
                    width: frame.width,
                    height: frame.height
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNoUI.toggle()
                    }
                }
                .onTapGesture(count: 2) {
                    withAnimation {
                        scale = scale <= 1 ? 2 : 1
                        lastScale = 1
                    }
                }
                .simultaneousGesture(magnifyGesture())
                .simultaneousGesture(dragCloseGesture())
        }
        .scrollDisabled(scale == 1)
        .frame(
            width: size.width,
            height: size.height
        )
        .ignoresSafeArea()
    }

    private func getImageFrame() -> CGSize {
        let imageAspect = CGFloat(item.width) / CGFloat(item.height)
        let screenAspect = size.width / size.height
        if imageAspect >= screenAspect {
            // wide image
            return CGSize(width: size.width * scale, height: size.width * scale / imageAspect)
        } else {
            // tall image
            return CGSize(width: size.height * scale * imageAspect, height: size.height * scale)
        }
    }

    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // avoid changing item during pinch
                swipeDisabled = true

                let delta = value.magnification / lastScale
                // To minimize jittering
                if abs(1 - delta) > 0.01 {
                    scale *= delta
                }
                lastScale = value.magnification
            }
            .onEnded { _ in
                swipeDisabled = false

                lastScale = 1
                if scale < 1 {
                    withAnimation {
                        scale = 1
                    }
                }
            }
    }

    private func dragCloseGesture() -> some Gesture {
        DragGesture()
            .onEnded { value in
                guard scale == 1 else { return }

                let w = abs(value.translation.width), h = value.translation.height
                if h > 10, w < 20, w / h < 0.2 {
                    dismiss()
                }
            }
    }
}

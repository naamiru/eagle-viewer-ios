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
    let dismiss: (Item) -> Void
    
    @State private var isNoUI = false
    @State private var swipeDisabled = false
    @State private var mainScrollId: String?
    @State private var thumbnailScrollId: String?
    @State private var isThumbnailScrolling = false

    @State private var scale: CGFloat = 1
    
    private let prefetcher = ImagePrefetcher()
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    
    init(item: Item, items: [Item], dismiss: @escaping (Item) -> Void) {
        selectedItem = item
        self.items = items
        self.dismiss = dismiss
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
    
    private func dragCloseGesture() -> some Gesture {
        DragGesture()
            .onEnded { value in
                guard scale == 1 else { return }

                let w = abs(value.translation.width), h = value.translation.height
                if h > 10, w < 20, w / h < 0.2 {
                    dismiss(selectedItem)
                }
            }
    }
    
    private func onScaleChanged(_ scale: CGFloat) {
        self.scale = scale
    }
    
    var header: some View {
        VStack {
            HStack {
                Button(action: {
                    dismiss(selectedItem)
                }) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.primary)
                }
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .glassEffect(.regular.interactive())
                
                Spacer()
                
                Text(selectedItem.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if let imageURL = getImageURL(for: selectedItem) {
                    ShareLink(item: imageURL) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
                    .glassEffect(.regular.interactive())
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                (isNoUI ? Color.black : Color.white)
                    .ignoresSafeArea()
                
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(items, id: \.itemId) { item in
                            ItemImageView(item: item)
                                .zoomable(
                                    isSelected: item.itemId == mainScrollId,
                                    isNoUI: $isNoUI,
                                    onScaleChanged: onScaleChanged
                                )
                                .containerRelativeFrame(.horizontal)
                                .id(item.itemId)
                        }
                    }
                    .scrollTargetLayout()
                }
                .ignoresSafeArea()
                .scrollDisabled(scale != 1)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $mainScrollId)
                .onAppear {
                    // Force scroll position to update after view appears
                    mainScrollId = selectedItem.itemId
                }
                .simultaneousGesture(dragCloseGesture())
                
                if !isNoUI {
                    VStack {
                        header
                        Spacer()
                    }
                    .transition(.opacity)
                }
                
                if !isNoUI {
                    VStack {
                        Spacer()
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 3) {
                                let selectedIndex = items.firstIndex(where: { $0.itemId == selectedItem.itemId })
                                ForEach(Array(items.enumerated()), id: \.element.itemId) { index, item in
                                    let isSelected = !isThumbnailScrolling && item.itemId == selectedItem.itemId
                                    let isBeforeSelected = selectedIndex != nil && !isThumbnailScrolling && index < selectedIndex!
                                    let isAfterSelected = selectedIndex != nil && !isThumbnailScrolling && index > selectedIndex!
                                    
                                    ItemThumbnailView(item: item)
                                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                        .aspectRatio(isSelected ? 1.0 : 0.7, contentMode: .fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                        .contentShape(RoundedRectangle(cornerRadius: 3))
                                        .offset(x: isBeforeSelected ? -8 : (isAfterSelected ? 8 : 0))
                                        .animation(.easeInOut(duration: 0.2), value: selectedItem.itemId)
                                        .animation(.easeInOut(duration: 0.2), value: isThumbnailScrolling)
                                        .onTapGesture {
                                            thumbnailScrollId = item.itemId
                                        }
                                        .id(item.itemId)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $thumbnailScrollId, anchor: .center)
                        .safeAreaPadding(.horizontal, geometry.size.width / 2 - 15)
                        .frame(height: 30)
                        .frame(minWidth: geometry.size.width)
                        .clipShape(.rect)
                        .mask {
                            LinearGradient(gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.02),
                                .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.92),
                                .init(color: .clear, location: 0.98),
                            ]), startPoint: .leading, endPoint: .trailing)
                        }
                        .onAppear {
                            // Force scroll position to update after view appears
                            // (when initialized + UI enabled)
                            thumbnailScrollId = nil
                            DispatchQueue.main.async {
                                thumbnailScrollId = selectedItem.itemId
                                isThumbnailScrolling = false
                            }
                        }
                        .onChange(of: geometry.size) {
                            // Force scroll position to update after rotate screen
                            thumbnailScrollId = nil
                            DispatchQueue.main.async {
                                thumbnailScrollId = selectedItem.itemId
                                isThumbnailScrolling = false
                            }
                        }
                        .onScrollPhaseChange { lastPhase, newPhase in
                            // detect if thumbnails slider is scrolled by user
                            
                            if lastPhase == .idle && newPhase == .animating {
                                // when main scrolled: .idle -> .animating -> .idle
                                isThumbnailScrolling = false
                            } else {
                                // when thumbnail scrolled: .idle -> .interacting -> .decelerating -> .idle
                                isThumbnailScrolling = newPhase != .idle
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .statusBar(hidden: isNoUI)
        .onAppear {
            prefetchAdjacentImages(for: selectedItem)
        }
        .onDisappear {
            prefetcher.stopPrefetching()
        }
        
        // sync main scroll / thumbnails scroll / selectedItem
        .onChange(of: mainScrollId) {
            if let newId = mainScrollId, let item = items.first(where: { $0.itemId == newId }) {
                selectedItem = item
            }
        }
        .onChange(of: thumbnailScrollId) {
            if let newId = thumbnailScrollId, let item = items.first(where: { $0.itemId == newId }) {
                selectedItem = item
            }
        }
        .onChange(of: selectedItem) {
            prefetchAdjacentImages(for: selectedItem)
            mainScrollId = selectedItem.itemId
            withAnimation(.easeInOut(duration: 0.2)) {
                thumbnailScrollId = selectedItem.itemId
            }
        }
    }
}

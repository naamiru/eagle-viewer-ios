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

    @State private var isInfoPresented = false
    @State private var isNoUIBeforeTextItem: Bool?
    
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
            if !ItemVideoView.isVideo(item: prevItem),
               !prevItem.isTextFile,
               let prevURL = getImageURL(for: prevItem)
            {
                urlsToPrefetch.append(prevURL)
            }
        }
        
        if currentIndex < items.count - 1 {
            let nextItem = items[currentIndex + 1]
            if !ItemVideoView.isVideo(item: nextItem),
               !nextItem.isTextFile,
               let nextURL = getImageURL(for: nextItem)
            {
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
                guard !selectedItem.isTextFile else { return }

                let w = abs(value.translation.width), h = value.translation.height
                if h > 10, w < 20, w / h < 0.2 {
                    dismiss(selectedItem)
                }
            }
    }
    
    private func onScaleChanged(_ scale: CGFloat) {
        self.scale = scale
    }

    private func handleItemChange(oldItem: Item?, newItem: Item) {
        // テキストファイル表示時の isNoUI 管理
        let oldIsText = oldItem?.isTextFile == true
        let newIsText = newItem.isTextFile

        if !oldIsText && newIsText {
            // 画像/動画 → テキスト: 保存してUIを表示
            isNoUIBeforeTextItem = isNoUI
            isNoUI = false
        } else if oldIsText && !newIsText {
            // テキスト → 画像/動画: 復元
            if let saved = isNoUIBeforeTextItem {
                isNoUI = saved
                isNoUIBeforeTextItem = nil
            }
        }
        // テキスト → テキスト: 何もしない

        prefetchAdjacentImages(for: newItem)
        mainScrollId = newItem.itemId
        withAnimation(.easeInOut(duration: 0.2)) {
            thumbnailScrollId = newItem.itemId
        }
    }

    private var backgroundColor: Color {
        if selectedItem.isTextFile {
            return Color(.systemBackground)
        }

        return isNoUI ? .black : Color(.systemBackground)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let titleMaxWidth = max(0, geometry.size.width - 160)
            let titleButton = Button(action: {
                isInfoPresented.toggle()
            }) {
                HStack(spacing: 8) {
                    Text(selectedItem.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "info.circle")
                        .font(.body.weight(.regular))
                }
                .foregroundColor(.primary)
                .frame(height: 44)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .regularGlassEffect(interactive: true)

            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(items, id: \.itemId) { item in
                            let isItemSelected = (mainScrollId ?? selectedItem.itemId) == item.itemId

                            Group {
                                if ItemVideoView.isVideo(item: item) {
                                    ItemVideoView(
                                        item: item,
                                        isSelected: isItemSelected,
                                        isNoUI: $isNoUI
                                    )
                                } else if item.isTextFile {
                                    ItemTextView(
                                        item: item,
                                        isSelected: isItemSelected
                                    )
                                } else {
                                    ItemImageView(
                                        item: item,
                                        isSelected: isItemSelected
                                    )
                                    .zoomable(
                                        isSelected: isItemSelected,
                                        isNoUI: $isNoUI,
                                        onScaleChanged: onScaleChanged
                                    )
                                }
                            }
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
                        Spacer()
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 3) {
                                let selectedIndex = items.firstIndex(where: { $0.itemId == selectedItem.itemId })
                                ForEach(Array(items.enumerated()), id: \.element.itemId) { index, item in
                                    let isSelected = !isThumbnailScrolling && item.itemId == selectedItem.itemId
                                    let isBeforeSelected = selectedIndex != nil && !isThumbnailScrolling && index < selectedIndex!
                                    let isAfterSelected = selectedIndex != nil && !isThumbnailScrolling && index > selectedIndex!
                                    
                                    ItemThumbnailView(item: item, textThumbnailStyle: .detailSlider)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss(selectedItem)
                    }) {
                        Image(systemName: "chevron.down")
                            .foregroundColor(.primary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    ViewThatFits(in: .horizontal) {
                        titleButton
                        titleButton.frame(maxWidth: titleMaxWidth)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if let imageURL = getImageURL(for: selectedItem) {
                        ShareLink(item: imageURL) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .toolbar(isNoUI ? .hidden : .visible, for: .navigationBar)
        }
        .sheet(isPresented: $isInfoPresented) {
            ItemInfoView(item: selectedItem)
                .presentationDetents([.medium, .large])
        }
        .navigationBarTitleDisplayMode(.inline)
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
        .onChange(of: selectedItem) { oldItem, newItem in
            handleItemChange(oldItem: oldItem, newItem: newItem)
        }
    }
}

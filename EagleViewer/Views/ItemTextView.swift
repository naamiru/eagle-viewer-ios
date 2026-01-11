//
//  ItemTextView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import MarkdownUI
import SwiftUI
import UIKit

struct ItemTextView: View {
    let item: Item
    let isSelected: Bool
    @Binding var isNoUI: Bool

    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @Environment(\.rootSafeAreaInsets) private var rootSafeAreaInsets
    @State private var textContent: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isMarkdownReady = false

    private var fileURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    var body: some View {
        Group {
            if let textContent {
                if item.isMarkdownFile {
                    if isMarkdownReady {
                        MarkdownScrollContentView(
                            markdown: textContent,
                            baseURL: fileURL?.deletingLastPathComponent(),
                            imageBaseURL: fileURL?.deletingLastPathComponent(),
                            isSelected: isSelected,
                            isNoUI: $isNoUI,
                            topPadding: rootSafeAreaInsets.top + 70,
                            horizontalPadding: 20,
                            bottomPadding: rootSafeAreaInsets.bottom + 24
                        )
                    } else {
                        ProgressView()
                    }
                } else {
                    SelectableTextView(
                        text: textContent,
                        isSelected: isSelected,
                        isNoUI: $isNoUI,
                        contentInset: UIEdgeInsets(
                            top: rootSafeAreaInsets.top + 70,
                            left: 20,
                            bottom: rootSafeAreaInsets.bottom + 24,
                            right: 20
                        )
                    )
                }
            } else if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundColor(.secondary)
                    Text(errorMessage ?? "Unable to load text file.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .task(id: item.itemId) {
            await loadText()
        }
    }

    private func loadText() async {
        await MainActor.run {
            isLoading = true
            textContent = nil
            errorMessage = nil
            isMarkdownReady = !item.isMarkdownFile
        }

        guard let fileURL else {
            await MainActor.run {
                isLoading = false
                errorMessage = "File not available."
            }
            return
        }

        do {
            let data = try await CloudFile.fileData(at: fileURL)
            let decoded = decodeText(from: data)
            await MainActor.run {
                if let decoded {
                    textContent = decoded
                } else {
                    errorMessage = "Unable to decode text file."
                }
            }
            if item.isMarkdownFile, decoded != nil {
                await MainActor.run {
                    isMarkdownReady = true
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func decodeText(from data: Data) -> String? {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = String(data: data, encoding: .utf16) {
            return string
        }
        if let string = String(data: data, encoding: .isoLatin1) {
            return string
        }
        return nil
    }
}

private struct MarkdownScrollContentView: View {
    let markdown: String
    let baseURL: URL?
    let imageBaseURL: URL?
    let isSelected: Bool
    @Binding var isNoUI: Bool
    let topPadding: CGFloat
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat

    @State private var suppressToggleUntil: Date = .distantPast
    @State private var lastScrollEnd: Date = .distantPast
    @State private var lastLinkTap: Date = .distantPast

    var body: some View {
        ScrollView(.vertical) {
            Markdown(markdown, baseURL: baseURL, imageBaseURL: imageBaseURL)
                .textSelection(.enabled)
                .environment(
                    \.openURL,
                    OpenURLAction { _ in
                        lastLinkTap = Date()
                        return .systemAction
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, topPadding)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
        }
        .scrollIndicators(.visible)
        .onScrollPhaseChange { oldPhase, newPhase in
            // Suppress tap toggle during scrolling
            if newPhase == .interacting || newPhase == .decelerating {
                suppressToggleUntil = Date().addingTimeInterval(0.2)
            }

            // Record scroll end time
            if oldPhase != .idle && newPhase == .idle {
                lastScrollEnd = Date()
                suppressToggleUntil = lastScrollEnd.addingTimeInterval(0.2)
            }
        }
        .simultaneousGesture(longPressGesture)
        .simultaneousGesture(tapGesture)
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .onEnded { _ in
                suppressToggleUntil = Date().addingTimeInterval(0.4)
            }
    }

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                handleTap()
            }
    }

    private func handleTap() {
        DispatchQueue.main.async {
            guard isSelected else { return }
            guard Date() >= suppressToggleUntil else { return }
            if Date().timeIntervalSince(lastScrollEnd) < 0.2 {
                return
            }
            if Date().timeIntervalSince(lastLinkTap) < 0.2 {
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                isNoUI.toggle()
            }
        }
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String
    let isSelected: Bool
    @Binding var isNoUI: Bool
    let contentInset: UIEdgeInsets

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = true
        view.backgroundColor = .white
        view.textColor = UIColor.label
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = contentInset
        view.delegate = context.coordinator
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = context.coordinator
        view.addGestureRecognizer(tapGesture)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.textContainerInset != contentInset {
            uiView.textContainerInset = contentInset
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isSelected: { isSelected }, isNoUI: $isNoUI)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        private let isSelected: () -> Bool
        private var isNoUI: Binding<Bool>
        private var suppressToggleUntil: Date = .distantPast
        private var lastScrollEnd: Date = .distantPast

        init(isSelected: @escaping () -> Bool, isNoUI: Binding<Bool>) {
            self.isSelected = isSelected
            self.isNoUI = isNoUI
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            suppressToggleUntil = Date().addingTimeInterval(0.2)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if decelerate {
                suppressToggleUntil = Date().addingTimeInterval(0.4)
            } else {
                lastScrollEnd = Date()
                suppressToggleUntil = lastScrollEnd.addingTimeInterval(0.2)
            }
        }

        func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
            suppressToggleUntil = Date().addingTimeInterval(0.4)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            lastScrollEnd = Date()
            suppressToggleUntil = lastScrollEnd.addingTimeInterval(0.2)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            suppressToggleUntil = Date().addingTimeInterval(0.3)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            suppressToggleUntil = Date().addingTimeInterval(0.3)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard isSelected() else { return }
            guard Date() >= suppressToggleUntil else { return }
            guard let textView = gesture.view as? UITextView else { return }
            guard !textView.isDragging, !textView.isDecelerating else { return }
            if Date().timeIntervalSince(lastScrollEnd) < 0.2 {
                return
            }
            guard textView.selectedRange.length == 0 else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isNoUI.wrappedValue.toggle()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

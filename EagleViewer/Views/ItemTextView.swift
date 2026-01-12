//
//  ItemTextView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import SwiftUI
import Textual
import UIKit

struct ItemTextView: View {
    let item: Item
    let isSelected: Bool
    let onDismiss: () -> Void

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
        let topPaddingOffset: CGFloat = rootSafeAreaInsets.top > 30 ? 62 : 80

        Group {
            if let textContent {
                if item.isMarkdownFile && !isMarkdownReady {
                    ProgressView()
                } else {
                    TextScrollContentView(
                        content: textContent,
                        isMarkdown: item.isMarkdownFile,
                        topPadding: rootSafeAreaInsets.top + topPaddingOffset,
                        leadingPadding: rootSafeAreaInsets.leading + 20,
                        trailingPadding: rootSafeAreaInsets.trailing + 20,
                        bottomPadding: rootSafeAreaInsets.bottom + 40,
                        onDismiss: onDismiss
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

private struct TextScrollContentView: View {
    let content: String
    let isMarkdown: Bool
    let topPadding: CGFloat
    let leadingPadding: CGFloat
    let trailingPadding: CGFloat
    let bottomPadding: CGFloat
    let onDismiss: () -> Void

    @State private var isDragToCloseEnabled = false
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            Group {
                if isMarkdown {
                    StructuredText(markdown: content)
                        .textual.textSelection(.enabled)
                } else {
                    TextViewRepresentable(text: content)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .padding(.leading, leadingPadding)
            .padding(.trailing, trailingPadding)
            .padding(.bottom, bottomPadding)
        }
        .scrollIndicators(.visible)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { oldValue, newValue in
            scrollOffset = newValue

            // Disable if scrolled downward during gesture
            if isDragToCloseEnabled && newValue > 0 {
                isDragToCloseEnabled = false
            }
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            if oldPhase == .idle && newPhase == .interacting {
                // Enable only if drag started at top
                isDragToCloseEnabled = (scrollOffset <= 0)
            } else if oldPhase == .interacting && newPhase == .decelerating {
                // Check threshold when finger is released
                if isDragToCloseEnabled && scrollOffset < -40 {
                    onDismiss()
                }
                isDragToCloseEnabled = false
            } else if newPhase == .idle {
                isDragToCloseEnabled = false
            }
        }
    }
}

private struct TextViewRepresentable: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textColor = UIColor.label
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.textContainer.lineBreakMode = .byWordWrapping
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
}

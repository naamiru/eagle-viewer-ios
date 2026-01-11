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
                        topPadding: rootSafeAreaInsets.top + 70,
                        horizontalPadding: 20,
                        bottomPadding: rootSafeAreaInsets.bottom + 24
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
    let topPadding: CGFloat
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat

    var body: some View {
        ScrollView(.vertical) {
            StructuredText(markdown: markdown)
                .textual.textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, topPadding)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
        }
        .scrollIndicators(.visible)
    }
}

private struct SelectableTextView: View {
    let text: String
    let topPadding: CGFloat
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat

    var body: some View {
        TextViewRepresentable(text: text)
            .padding(.top, topPadding)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
    }
}

private struct TextViewRepresentable: UIViewRepresentable {
    let text: String

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
        view.textContainerInset = .zero
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
}

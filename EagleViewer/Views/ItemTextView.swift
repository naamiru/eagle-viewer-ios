//
//  ItemTextView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import SwiftUI
import UIKit

struct ItemTextView: View {
    let item: Item
    let isSelected: Bool

    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @Environment(\.rootSafeAreaInsets) private var rootSafeAreaInsets
    @State private var textContent: String?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var fileURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    var body: some View {
        Group {
            if let textContent {
                SelectableTextView(
                    text: textContent,
                    isSelected: isSelected,
                    contentInset: UIEdgeInsets(
                        top: rootSafeAreaInsets.top + 70,
                        left: 20,
                        bottom: rootSafeAreaInsets.bottom + 24,
                        right: 20
                    )
                )
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
        .onAppear {
        }
        .onChange(of: isSelected) { _, newValue in
        }
    }

    @MainActor
    private func loadText() async {
        isLoading = true
        textContent = nil
        errorMessage = nil

        guard let fileURL else {
            isLoading = false
            errorMessage = "File not available."
            return
        }

        do {
            let data = try await CloudFile.fileData(at: fileURL)
            if let decoded = decodeText(from: data) {
                textContent = decoded
            } else {
                errorMessage = "Unable to decode text file."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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

private struct SelectableTextView: UIViewRepresentable {
    let text: String
    let isSelected: Bool
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
        Coordinator(isSelected: { isSelected })
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let isSelected: () -> Bool

        init(isSelected: @escaping () -> Bool) {
            self.isSelected = isSelected
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isSelected() else { return }
        }
    }
}

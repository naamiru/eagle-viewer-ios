//
//  ItemTextView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import SwiftUI

private struct TextScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ItemTextView: View {
    let item: Item
    let isSelected: Bool
    @Binding var isAtTop: Bool

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: TextScrollOffsetKey.self,
                                    value: proxy.frame(in: .named("textScroll")).minY
                                )
                        }
                        .frame(height: 0)

                        Color.clear
                            .frame(height: rootSafeAreaInsets.top + 70)

                        Text(verbatim: textContent)
                            .font(.body)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, rootSafeAreaInsets.bottom + 24)
                    }
                }
                .coordinateSpace(name: "textScroll")
                .onPreferenceChange(TextScrollOffsetKey.self) { offset in
                    guard isSelected else { return }
                    isAtTop = offset >= -1
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
        .background(Color(.secondarySystemBackground))
        .task(id: item.itemId) {
            await loadText()
        }
        .onAppear {
            if isSelected {
                isAtTop = true
            }
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                isAtTop = true
            }
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

//
//  LibraryAddView.swift
//  EagleViewer
//
//  Created on 2025/08/22
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct LibraryAddView: View {
    enum Destination: Hashable {
        case folderSelect
    }

    @State private var libraryName: String?
    @State private var librarySource: LibrarySource?
    @State private var useLocalStorage = true

    @State private var isLoading = false
    @State private var path = NavigationPath()

    @Environment(\.repositories) private var repositories
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Library") {
                    NavigationLink(value: Destination.folderSelect) {
                        LabeledContent("Eagle Library Folder") {
                            Text(libraryName ?? "")
                        }
                    }
                }

                Section(
                    header: Text("Options"),
                    footer: Text("Recommended for slow external storage or network drives."),
                    content: {
                        Toggle("Download images locally", isOn: $useLocalStorage)
                            .disabled(isCloudSource)
                    }
                )
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .folderSelect:
                    LibraryFolderSelectView { name, source in
                        self.libraryName = name
                        self.librarySource = source

                        if case .gdrive = source {
                            self.useLocalStorage = true
                        }
                        if case .onedrive = source {
                            self.useLocalStorage = true
                        }

                        // Pop back to root
                        path = NavigationPath()
                    }
                }
            }
            .navigationTitle("Add new library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let data = validFormData {
                            isLoading = true
                            Task {
                                do {
                                    try await createLibrary(name: data.name, source: data.source, useLocalStorage: data.useLocalStorage)
                                } catch {
                                    Logger.app.error("Failed to create library: \(error)")
                                }
                                await MainActor.run {
                                    isLoading = false
                                }
                            }
                        }
                    }
                    .disabled(validFormData == nil || isLoading)
                }
            }
        }
    }

    private var validFormData: (name: String, source: LibrarySource, useLocalStorage: Bool)? {
        guard let libraryName, let librarySource else {
            return nil
        }
        return (libraryName, librarySource, useLocalStorage)
    }

    private var isCloudSource: Bool {
        switch librarySource {
        case .gdrive, .onedrive:
            true
        default:
            false
        }
    }

    private func createLibrary(name: String, source: LibrarySource, useLocalStorage: Bool) async throws {
        // Create library
        let newLibrary = try await repositories.library.create(
            name: name,
            source: source,
            useLocalStorage: isCloudSource ? true : useLocalStorage
        )

        await MainActor.run {
            // Set the newly created library as active
            settingsManager.setActiveLibrary(id: newLibrary.id)
            dismiss()
        }
    }
}

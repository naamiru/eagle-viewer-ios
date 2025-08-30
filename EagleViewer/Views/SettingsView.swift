//
//  SettingsView.swift
//  EagleViewer
//
//  Created on 2025/08/26
//

import SwiftUI

struct SettingsView: View {
    enum Destination: Hashable {
        case folderSelect
    }

    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.repositories) private var repositories
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var metadataImportManager: MetadataImportManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @State private var showingLibraries = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Library") {
                    NavigationLink(value: Destination.folderSelect) {
                        LabeledContent("Eagle Library Folder") {
                            Text(library.name)
                        }
                    }

                    Toggle("Download images locally", isOn: .constant(library.useLocalStorage))
                        .disabled(true)

                    Button("Change Library...") {
                        showingLibraries = true
                    }
                    .foregroundColor(.accentColor)
                }

                Section("Sync") {
                    LabeledContent("Status") {
                        if metadataImportManager.isImporting {
                            HStack(spacing: 8) {
                                ProgressView(value: metadataImportManager.importProgress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 60)
                                Text(verbatim: "\(Int(metadataImportManager.importProgress * 100))%")
                            }
                        } else {
                            Text(library.lastImportStatus.displayText)
                        }
                    }

                    if metadataImportManager.isImporting {
                        Button("Stop Syncing") {
                            metadataImportManager.cancelImporting()
                        }
                        .foregroundColor(.red)
                    } else {
                        Menu {
                            Button("Sync New & Modified") {
                                startImporting(fullImport: false)
                            }

                            Button("Full Resync") {
                                startImporting(fullImport: true)
                            }
                        } label: {
                            Text("Sync Now...")
                                .foregroundColor(.accentColor)
                        }
                        .disabled(libraryFolderManager.accessState != .open)
                    }
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .folderSelect:
                    LibraryFolderSelectView { name, bookmarkData in
                        updateLibraryFolder(name: name, bookmarkData: bookmarkData)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingLibraries) {
                LibrariesView()
            }
        }
    }

    private func startImporting(fullImport: Bool) {
        _ = Task {
            await metadataImportManager.startImporting(
                library: library,
                activeLibraryURL: libraryFolderManager.activeLibraryURL,
                dbWriter: repositories.dbWriter,
                fullImport: fullImport
            )
        }
    }

    private func updateLibraryFolder(name: String, bookmarkData: Data) {
        Task {
            do {
                try await repositories.library.updateFolder(id: library.id, name: name, bookmarkData: bookmarkData)
                path = NavigationPath()
            } catch {
                // Handle error
            }
        }
    }
}

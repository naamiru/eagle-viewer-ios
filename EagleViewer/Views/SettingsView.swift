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

    @State private var librarySourceKind: LibrarySource.Kind = .file
    @State private var isSignedInGoogleDrive = false
    @State private var isSigningInGoogleDrive = false

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

                if librarySourceKind != .file {
                    Section {
                        if librarySourceKind == .gdrive {
                            LabeledContent("Google Drive") {
                                if isSignedInGoogleDrive {
                                    Text("Signed in")
                                } else {
                                    Text("Signed out")
                                }
                            }
                            if isSignedInGoogleDrive {
                                Button("Sign out", role: .destructive) {
                                    signOutGoogle()
                                }
                            } else {
                                Button("Sign in...") {
                                    signInGoogle()
                                }
                                .disabled(isSigningInGoogleDrive)
                            }
                        }
                    } header: {
                        Text("Linked Accounts")
                    } footer: {
                        if librarySourceKind == .gdrive {
                            GooglePrivacyNoticeView()
                                .padding(.top, 6)
                        }
                    }
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .folderSelect:
                    LibraryFolderSelectView { name, source in
                        updateLibrarySource(name: name, source: source)
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
            .onChange(of: library.source, initial: true) { _, source in
                switch source {
                case .file:
                    librarySourceKind = .file
                case .gdrive:
                    librarySourceKind = .gdrive
                    Task {
                        let isSignedIn = await GoogleAuthManager.isSignedIn()
                        await MainActor.run {
                            isSignedInGoogleDrive = isSignedIn
                        }
                    }
                }
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

    private func updateLibrarySource(name: String, source: LibrarySource) {
        Task {
            do {
                try await repositories.library.updateSource(id: library.id, name: name, source: source)
                path = NavigationPath()
            } catch {
                // Handle error
            }
        }
    }

    private func signOutGoogle() {
        GoogleAuthManager.signOut()
        isSignedInGoogleDrive = false
    }

    private func signInGoogle() {
        isSigningInGoogleDrive = true
        Task {
            if let _ = try? await GoogleAuthManager.ensureSignedIn() {
                await MainActor.run {
                    isSignedInGoogleDrive = true
                }
            }
            await MainActor.run {
                isSigningInGoogleDrive = false
            }
        }
    }
}

struct GooglePrivacyNoticeView: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy Notice")
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)

            Text("When you connect your Google account, Eagle Viewer requests read-only access (drive.readonly) to your Google Drive.")
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !expanded {
                Button {
                    expanded = true
                } label: {
                    HStack(spacing: 6) {
                        Text("Learn more")
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .tint(.accentColor)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    bullet(String(localized: "Access is limited to the files or folders you explicitly select."))
                    bullet(String(localized: "All data is processed locally on your device."))
                    bullet(String(localized: "No Google Drive data is stored on our servers or shared with third parties."))
                    bullet(String(localized: "Our use of Google data complies with the Google API Services User Data Policy, including the Limited Use requirements."))
                    Link("See privacy policy", destination: URL(string: "https://eagle-viewer-ios.naamiru.com/privacypolicy/")!)
                        .font(.callout.weight(.semibold))
                        .padding(.top, 4)
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").font(.callout).foregroundStyle(.primary)
            Text(text).foregroundStyle(.primary)
        }
    }
}

//
//  FirstLaunchView.swift
//  EagleViewer
//
//  Created on 2025/08/27
//

import OSLog
import SwiftUI

struct FirstLaunchView: View {
    enum Destination: Hashable {
        case option(String, Data)
    }

    @State var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            LibraryFolderSelectView { name, data in
                path.append(.option(name, data))
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .option(let name, let data):
                    FirstLaunchInfoView(libraryName: name, bookmarkData: data)
                }
            }
        }
    }
}

struct FirstLaunchInfoView: View {
    let libraryName: String
    let bookmarkData: Data

    @State private var useLocalStorage: Bool = true
    @State private var isLoading = false

    @Environment(\.repositories) private var repositories
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("Select Options")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    Toggle("Download images locally", isOn: $useLocalStorage)
                        .padding(.horizontal)

                    Text("Recommended for slow external storage or network drives.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Divider()
                }

                Spacer(minLength: 12)

                Button(action: {
                    isLoading = true
                    Task {
                        do {
                            try await createLibrary(name: libraryName, bookmarkData: bookmarkData, useLocalStorage: useLocalStorage)
                        } catch {
                            Logger.app.error("Failed to create library: \(error)")
                        }
                        await MainActor.run {
                            isLoading = false
                        }
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22) // Match text height
                    } else {
                        Text("Import Library")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(isLoading)

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Library Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createLibrary(name: String, bookmarkData: Data, useLocalStorage: Bool) async throws {
        let newLibrary = try await repositories.library.create(name: name, bookmarkData: bookmarkData, useLocalStorage: useLocalStorage)

        await MainActor.run {
            settingsManager.setActiveLibrary(id: newLibrary.id)
        }
    }
}

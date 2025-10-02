//
//  LibraryFolderSelectView.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import OSLog
import SwiftUI

enum LibrarySelectionError: LocalizedError {
    case invalidFolderName
    case accessDenied
    case metadataNotFound
    case unsupportedVersion(String)
    case versionNotFound
    case emptyLibraryName
    
    var errorDescription: String? {
        switch self {
        case .invalidFolderName:
            return String(localized: "Please select a valid Eagle library folder (must end with .library)")
        case .accessDenied:
            return String(localized: "Failed to access folder")
        case .metadataNotFound:
            return String(localized: "metadata.json not found in the selected folder")
        case .unsupportedVersion(let version):
            return String(localized: "This app only supports Eagle version 4.x. Your library is using version \(version).")
        case .versionNotFound:
            return String(localized: "Unable to determine Eagle version from metadata.json")
        case .emptyLibraryName:
            return String(localized: "Invalid library folder name")
        }
    }
}

struct LibraryFolderSelectView: View {
    let onSelect: (String, Data) -> Void
    
    @State private var showingFilePicker = false
    @State private var error: Error?
    @State private var showingErrorAlert = false
    @State private var isProcessing = false
    @State private var selectionTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("Select your Eagle library folder")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your Eagle library folder must be accessible through the Files app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Rectangle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(height: 1)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Supported locations:")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 14) {
                            LocationItem(icon: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone",
                                         title: UIDevice.current.userInterfaceIdiom == .pad ? String(localized: "On My iPad") : String(localized: "On My iPhone"),
                                         description: String(localized: "Local storage on this device"))
                            LocationItem(icon: "icloud", title: String(localized: "iCloud Drive"), description: String(localized: "Synced across your Apple devices"))
                            LocationItem(icon: "externaldrive", title: String(localized: "External Storage"), description: String(localized: "Connected drives or network shares"))
                        }
                    }
                }
                .padding(24)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.06),
                            Color.blue.opacity(0.10)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: Color.blue.opacity(0.08), radius: 10, x: 0, y: 4)
                .padding(.horizontal)
                
                VStack(spacing: 16) {
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 22) // Match text height
                        } else {
                            Text("Browse for Eagle Library")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(isProcessing)
                    
                    HStack(spacing: 4) {
                        Text("Select a folder ending with \".library\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .onDisappear {
            selectionTask?.cancel()
            selectionTask = nil
            isProcessing = false
        }
        .alert("Error", isPresented: $showingErrorAlert, presenting: error) { _ in
            Button("OK") {
                error = nil
            }
        } message: { error in
            Text(error.localizedDescription)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleFolderSelection(url)
                }
            case .failure(let error):
                showError(error)
            }
        }
    }
    
    private func showError(_ error: Error) {
        self.error = error
        showingErrorAlert = true
        isProcessing = false
    }
    
    private func handleFolderSelection(_ url: URL) {
        isProcessing = true
        
        selectionTask?.cancel()
        selectionTask = Task {
            do {
                let (name, bookmarkData) = try await getLibraryInfo(url)
                
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    onSelect(name, bookmarkData)
                    isProcessing = false
                    selectionTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    showError(error)
                    isProcessing = false
                    selectionTask = nil
                }
            }
        }
    }
    
    private func getLibraryInfo(_ url: URL) async throws -> (name: String, bookmarkData: Data) {
        // Validate folder name ends with .library
        let folderName = url.lastPathComponent
        guard folderName.hasSuffix(".library") else {
            throw LibrarySelectionError.invalidFolderName
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            throw LibrarySelectionError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // Check Eagle version from metadata.json
        let metadataUrl = url.appending(path: "metadata.json", directoryHint: .notDirectory)
        
        // Check file existence
        guard await CloudFile.fileExists(at: metadataUrl) else {
            throw LibrarySelectionError.metadataNotFound
        }
        
        // Read metadata using URLSession
        let metadataData = try await CloudFile.fileData(at: metadataUrl)
        
        // Parse metadata to check version
        struct MetadataVersion: Decodable {
            let applicationVersion: String?
        }
        
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(MetadataVersion.self, from: metadataData)
        
        // Check if applicationVersion exists and starts with "4."
        if let version = metadata.applicationVersion {
            guard version.hasPrefix("4.") else {
                throw LibrarySelectionError.unsupportedVersion(version)
            }
        } else {
            throw LibrarySelectionError.versionNotFound
        }
        
        let bookmarkData = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        // Extract library name from the URL
        let libraryName = String(url.lastPathComponent.dropLast(8)) // Remove .library extension
        
        guard !libraryName.isEmpty else {
            throw LibrarySelectionError.emptyLibraryName
        }
        
        return (name: libraryName, bookmarkData: bookmarkData)
    }
}

struct LocationItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.10),
                                Color.blue.opacity(0.15)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.blue.opacity(0.7))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    LibraryFolderSelectView { name, bookmarkData in
        Logger.app.debug("Selected library '\(name)' with \(bookmarkData.count) bytes of bookmark data")
    }
}

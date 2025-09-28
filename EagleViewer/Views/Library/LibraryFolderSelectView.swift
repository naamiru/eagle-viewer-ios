//
//  LibraryFolderSelectView.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import GoogleAPIClientForREST_Drive
import GoogleSignIn
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

struct GoogleUserWrapper: Identifiable {
    let id: String
    let user: GIDGoogleUser

    init(_ user: GIDGoogleUser) {
        self.user = user
        self.id = user.userID ?? UUID().uuidString
    }
}

struct LibraryFolderSelectView: View {
    let onSelect: (String, LibrarySource) -> Void
    
    @State private var showingFilePicker = false
    @State private var googleDriveUser: GoogleUserWrapper?
    @State private var error: Error?
    @State private var showingErrorAlert = false
    @State private var isProcessingFile = false
    @State private var isProcessingGdrive = false
    @State private var selectionTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select your Eagle library folder")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                    
                    Text("Only folders ending with \".library\" can be selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("Select from Files app")
                        .fontWeight(.semibold)
                    
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
                    .cornerRadius(10)
                    .shadow(color: Color.blue.opacity(0.08), radius: 10, x: 0, y: 4)
                    
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        if isProcessingFile {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 22) // Match text height
                        } else {
                            Text("Select from Files app")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .disabled(isProcessingFile || isProcessingGdrive)
                }
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("Or choose a cloud service")
                        .fontWeight(.semibold)
                    
                    Button(action: {
                        showGoogleDrive()
                    }) {
                        HStack {
                            Image("GoogleDrive")
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: 22)
                            Spacer()
                            if isProcessingGdrive {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                    .frame(height: 22) // Match text height
                                    .padding(.trailing, 22)
                            } else {
                                Text("Google Drive")
                                    .padding(.trailing, 22)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity)
                    }
                    .contextMenu {
                        Button(role: .destructive, action: {
                            GoogleAuthManager.signOut()
                        }) {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.forward")
                        }
                    }
                    .controlSize(.large)
                    .buttonStyle(.glass)
                    .disabled(isProcessingFile || isProcessingGdrive)
                }
            }
            .padding(.horizontal)
        }
        .onDisappear {
            selectionTask?.cancel()
            selectionTask = nil
            isProcessingFile = false
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
        .sheet(item: $googleDriveUser) { user in
            GoogleDriveFolderPickerView(googleUser: user.user) { libraryName, fileId in
                handleGoogleDriveSelection(user: user.user, libraryName: libraryName, fileId: fileId)
                googleDriveUser = nil
            }
        }
    }
    
    private func showError(_ error: Error) {
        self.error = error
        showingErrorAlert = true
        isProcessingFile = false
        isProcessingGdrive = false
    }
    
    private func showGoogleDrive() {
        Task {
            if let user = try? await GoogleAuthManager.ensureSignedIn() {
                googleDriveUser = GoogleUserWrapper(user)
            } else {
                googleDriveUser = nil
            }
        }
    }
    
    private func handleGoogleDriveSelection(user: GIDGoogleUser, libraryName: String, fileId: String) {
        isProcessingGdrive = true
        selectionTask?.cancel()
        selectionTask = Task {
            do {
                try await LibraryValidator.validateMetadata(user: user, fileId: fileId)
                await MainActor.run {
                    onSelect(libraryName, .gdrive(fileId: fileId))
                    isProcessingGdrive = false
                    selectionTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    showError(error)
                    isProcessingGdrive = false
                    selectionTask = nil
                }
            }
        }
    }
    
    private func handleFolderSelection(_ url: URL) {
        isProcessingFile = true
        
        selectionTask?.cancel()
        selectionTask = Task {
            do {
                let (name, bookmarkData) = try await getLibraryInfo(url)
                
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    onSelect(name, .file(bookmarkData: bookmarkData))
                    isProcessingFile = false
                    selectionTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    showError(error)
                    isProcessingFile = false
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
        guard FileManager.default.fileExists(atPath: metadataUrl.path) else {
            throw LibrarySelectionError.metadataNotFound
        }
        
        // Read metadata using URLSession
        let (metadataData, _) = try await URLSession.shared.data(from: metadataUrl)
        
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
                                Color.clear.opacity(0.10),
                                Color.clear.opacity(0.15)
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

enum LibraryValidator {
    static func validateMetadata(_ data: Data) throws {
        // Parse metadata to check version
        struct MetadataVersion: Decodable {
            let applicationVersion: String?
        }
        
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(MetadataVersion.self, from: data)
        
        // Check if applicationVersion exists and starts with "4."
        if let version = metadata.applicationVersion {
            guard version.hasPrefix("4.") else {
                throw LibrarySelectionError.unsupportedVersion(version)
            }
        } else {
            throw LibrarySelectionError.versionNotFound
        }
    }
    
    static func validateMetadata(user: GIDGoogleUser, fileId: String) async throws {
        let service = GTLRDriveService()
        service.authorizer = user.fetcherAuthorizer
        let metadata = try await getMetadata(service: service, folderId: fileId)
        try validateMetadata(metadata)
    }
    
    private static func getMetadata(service: GTLRDriveService, folderId: String) async throws -> Data {
        let fileId = try await GoogleDriveUtils.getChildFileId(service: service, folderId: folderId, fileName: "metadata.json")
        return try await GoogleDriveUtils.getFileData(service: service, fileId: fileId)
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
        guard FileManager.default.fileExists(atPath: metadataUrl.path) else {
            throw LibrarySelectionError.metadataNotFound
        }
        
        // Read metadata using URLSession
        let (metadataData, _) = try await URLSession.shared.data(from: metadataUrl)
        
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

//
//  EagleViewerApp.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Nuke
import NukeVideo
import SwiftUI

@main
struct EagleViewerApp: App {
    @State private var repositories: Result<Repositories, Error>

    @Environment(\.scenePhase) var scenePhase
    @StateObject private var metadataImportManager = MetadataImportManager()

    init() {
        // initial setup

        // initialize DB
        _repositories = State(initialValue: Result {
            try Repositories.disk()
        })

        // enable Nule disk cache
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)

        // enable NukeVidee
        ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    }

    var body: some Scene {
        WindowGroup {
            switch repositories {
            case .success(let repos):
                ContentView()
                    .repositories(repos)
                    .environmentObject(SettingsManager.shared)
                    .environmentObject(LibraryFolderManager.shared)
                    .environmentObject(metadataImportManager)
                    .environmentObject(EventCenter.shared)
                    .detectOrientation()
                    .onChange(of: scenePhase) { _, newPhase in
                        switch newPhase {
                        case .active:
                            LibraryFolderManager.shared.resumeAccess()
                        case .background:
                            LibraryFolderManager.shared.stopAccess()
                        default:
                            break
                        }
                    }
            case .failure(let error):
                AppErrorView(error: error)
            }
        }
    }
}

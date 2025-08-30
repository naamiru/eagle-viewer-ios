//
//  ContentView.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import GRDB
import GRDBQuery
import OSLog
import SwiftUI

struct ContentView: View {
    @State private var activeLibraryRequest = ActiveLibraryRequest(activeLibraryId: nil)

    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        ContentInnerView(activeLibraryRequest: $activeLibraryRequest)
            .onChange(of: settingsManager.activeLibraryId, initial: true) {
                activeLibraryRequest.activeLibraryId = settingsManager.activeLibraryId
            }
    }
}

struct ContentInnerView: View {
    @Query<ActiveLibraryRequest> private var dbActiveLibrary: Library?
    @State private var activeLibrary: Library? = nil
    @EnvironmentObject private var folderManager: LibraryFolderManager
    @EnvironmentObject private var eventCenter: EventCenter

    init(activeLibraryRequest: Binding<ActiveLibraryRequest>) {
        _dbActiveLibrary = Query(activeLibraryRequest)
    }

    var body: some View {
        Group {
            if let activeLibrary {
                MainView()
                    .environment(\.library, activeLibrary)
            } else {
                FirstLaunchView()
            }
        }
        .onChange(of: dbActiveLibrary, initial: true) {
            if activeLibrary?.id != dbActiveLibrary?.id {
                eventCenter.post(.libraryWillChange(oldValue: activeLibrary, newValue: dbActiveLibrary))
            }

            activeLibrary = dbActiveLibrary
            folderManager.updateCurrentLibrary(dbActiveLibrary)
        }
    }
}

struct ActiveLibraryRequest: ValueObservationQueryable {
    var activeLibraryId: Int64?

    static var defaultValue: Library? { nil }

    func fetch(_ db: Database) throws -> Library? {
        if let activeLibraryId {
            let library = try Library
                .filter(Column("id") == activeLibraryId)
                .fetchOne(db)
            if library != nil {
                return library
            }
        }

        // fallback to any library
        return try Library.order(Column("sortOrder")).fetchOne(db)
    }
}

#Preview {
    ContentView()
        .repositories(.empty())
}

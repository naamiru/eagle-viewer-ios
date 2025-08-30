//
//  LibrariesView.swift
//  EagleViewer
//
//  Created on 2025/08/22
//

import GRDB
import GRDBQuery
import SwiftUI

struct LibrariesView: View {
    @Query(LibraryRequest()) var libraries: [Library]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.repositories) private var repositories
    @Environment(\.library) private var activeLibrary
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var showingAddLibrary = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(libraries) { library in
                    HStack {
                        Text(library.name)
                        Spacer()
                        if activeLibrary.id == library.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settingsManager.setActiveLibrary(id: library.id)
                        dismiss()
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task {
                                try? await repositories.library.delete(id: library.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteLibraries)
            }
            .listStyle(.inset)
            .navigationTitle("Libraries")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddLibrary = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddLibrary) {
                LibraryAddView()
            }
        }
    }

    private func deleteLibraries(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let library = libraries[index]
                try? await repositories.library.delete(id: library.id)
            }
        }
    }
}

struct LibraryRequest: ValueObservationQueryable {
    static var defaultValue: [Library] { [] }

    func fetch(_ db: Database) throws -> [Library] {
        return try Library.order(Column("sortOrder")).fetchAll(db)
    }
}

#Preview {
    LibrariesView()
        .repositories(.empty())
}

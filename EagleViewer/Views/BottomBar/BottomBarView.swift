//
//  BottomBarView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import SwiftUI

struct BottomBarView: View {
    var body: some View {
        Grid {
            GridRow {
                HomeButton()
                SortMenu()
                LayoutMenu()
                RefreshButton()
            }
        }
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(UIColor.separator)),
            alignment: .top
        )
    }
}

struct HomeButton: View {
    @EnvironmentObject private var navigationManager: NavigationManager

    var body: some View {
        Button(action: {
            navigationManager.popToRoot()
        }) {
            Image(systemName: "house")
                .foregroundColor(navigationManager.path.count == 0 ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
        }
    }
}

struct SortMenu: View {
    @EnvironmentObject private var navigationManager: NavigationManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var eventCenter: EventCenter

    var globalSortOption: GlobalSortOption { settingsManager.globalSortOption }
    var folderSortOption: FolderSortOption { settingsManager.folderSortOption }

    var body: some View {
        switch navigationManager.path.last {
        case .folder(let id):
            FolderItemSortMenuView(folderId: id.folderId)
        case .all, .uncategorized:
            Menu {
                ForEach(GlobalSortType.allCases.reversed(), id: \.self) { type in
                    Button(action: {
                        if globalSortOption.type == type {
                            // Toggle ascending if same type is reselected
                            settingsManager.setGlobalSortOption(
                                GlobalSortOption(type: type, ascending: !globalSortOption.ascending)
                            )
                        } else {
                            // Inherit current ascending value for new type
                            settingsManager.setGlobalSortOption(
                                GlobalSortOption(type: type, ascending: true)
                            )
                        }
                        eventCenter.post(.globalSortChanged)
                    }) {
                        if globalSortOption.type == type {
                            Label(type.displayName, systemImage: globalSortOption.ascending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(type.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(Color.primary)
                    .background(Color.clear)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
        case nil:
            // in HomeView
            Menu {
                ForEach(FolderSortType.allCases.reversed(), id: \.self) { type in
                    Button(action: {
                        if folderSortOption.type == type {
                            // Toggle ascending if same type is reselected
                            settingsManager.setFolderSortOption(
                                FolderSortOption(type: type, ascending: !folderSortOption.ascending)
                            )
                        } else {
                            // Inherit current ascending value for new type
                            settingsManager.setFolderSortOption(
                                FolderSortOption(type: type, ascending: true)
                            )
                        }
                    }) {
                        if folderSortOption.type == type {
                            Label(type.displayName, systemImage: folderSortOption.ascending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(type.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(Color.primary)
                    .background(Color.clear)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
        default:
            Button(action: {}) {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(Color.secondary)
            }
            .disabled(true)
        }
    }
}

struct LayoutMenu: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @Environment(\.isPortrait) private var isPortrait

    var body: some View {
        Menu {
            ForEach(Layout.allCases.reversed(), id: \.self) { layout in
                Button(action: {
                    settingsManager.setLayout(layout)
                }) {
                    let columnCount = layout.columnCount(isPortrait: isPortrait)
                    let displayName = String(localized: "\(columnCount) Columns")
                    if settingsManager.layout == layout {
                        Label(displayName, systemImage: "checkmark")
                    } else {
                        Text(displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .foregroundColor(Color.primary)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
    }
}

struct RefreshButton: View {
    @Environment(\.library) private var library
    @Environment(\.repositories) private var repositories
    @EnvironmentObject private var metadataImportManager: MetadataImportManager
    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager

    var body: some View {
        if libraryFolderManager.accessState == .opening ||
            // importProgress == 0  while establishing folder access if library is local
            (metadataImportManager.isImporting && metadataImportManager.importProgress == 0)
        {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if metadataImportManager.isImporting {
            Menu {
                Button("Stop Syncing", role: .destructive) {
                    metadataImportManager.cancelImporting()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)

                    Circle()
                        .trim(from: 0, to: metadataImportManager.importProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))

                    Text(verbatim: "\(Int(metadataImportManager.importProgress * 100))")
                        .font(.system(size: 8, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Menu {
                Button("Full Resync") {
                    startImporting(fullImport: true)
                }
                Button("Sync New & Modified") {
                    startImporting(fullImport: false)
                }
            } label: {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .foregroundColor(Color.primary)
                    .frame(maxWidth: .infinity)
            } primaryAction: {
                startImporting(fullImport: false)
            }
        }
    }

    private func startImporting(fullImport: Bool) {
        _ = Task {
            // establish folder access if not yet
            _ = try await libraryFolderManager.getActiveLibraryURL()
            await metadataImportManager.startImporting(
                library: library,
                activeLibraryURL: libraryFolderManager.activeLibraryURL,
                dbWriter: repositories.dbWriter,
                fullImport: fullImport
            )
        }
    }
}

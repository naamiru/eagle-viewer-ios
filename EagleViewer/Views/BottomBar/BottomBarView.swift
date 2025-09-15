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
                SearchButton()
            }
        }
        .background(
            Color(UIColor.systemBackground)
                .ignoresSafeArea(edges: .horizontal)
        )
        .overlay(
            Rectangle()
                .ignoresSafeArea(edges: .horizontal)
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

struct SearchButton: View {
    @EnvironmentObject private var searchManager: SearchManager

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                searchManager.showSearch()
            }
        }) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.primary)
                .frame(maxWidth: .infinity)
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

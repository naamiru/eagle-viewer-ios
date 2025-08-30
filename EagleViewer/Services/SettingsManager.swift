//
//  SettingsManager.swift
//  EagleViewer
//
//  Created on 2025/08/23
//

import Foundation

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published private(set) var activeLibraryId: Int64?
    @Published private(set) var globalSortOption: GlobalSortOption
    @Published private(set) var folderSortOption: FolderSortOption
    @Published private(set) var layout: Layout

    private init() {
        if let storedValue = UserDefaults.standard.object(forKey: "activeLibraryId") as? Int {
            self.activeLibraryId = Int64(storedValue)
        } else {
            self.activeLibraryId = nil
        }

        let sortType = UserDefaults.standard.string(forKey: "globalSortType")
            .flatMap { GlobalSortType(rawValue: $0) } ?? GlobalSortOption.defaultValue.type
        let ascending = UserDefaults.standard.object(forKey: "globalSortAscending") as? Bool ?? GlobalSortOption.defaultValue.ascending
        self.globalSortOption = GlobalSortOption(type: sortType, ascending: ascending)

        let folderSortType = UserDefaults.standard.string(forKey: "folderSortType")
            .flatMap { FolderSortType(rawValue: $0) } ?? FolderSortOption.defaultValue.type
        let folderAscending = UserDefaults.standard.object(forKey: "folderSortAscending") as? Bool ?? FolderSortOption.defaultValue.ascending
        self.folderSortOption = FolderSortOption(type: folderSortType, ascending: folderAscending)
        
        self.layout = UserDefaults.standard.string(forKey: "layout")
            .flatMap { Layout(rawValue: $0) } ?? Layout.defaultValue
    }

    func setActiveLibrary(id: Int64?) {
        activeLibraryId = id
        if let id {
            UserDefaults.standard.set(Int(id), forKey: "activeLibraryId")
        } else {
            UserDefaults.standard.removeObject(forKey: "activeLibraryId")
        }
    }

    func setGlobalSortOption(_ option: GlobalSortOption) {
        globalSortOption = option
        UserDefaults.standard.set(option.type.rawValue, forKey: "globalSortType")
        UserDefaults.standard.set(option.ascending, forKey: "globalSortAscending")
    }

    func setFolderSortOption(_ option: FolderSortOption) {
        folderSortOption = option
        UserDefaults.standard.set(option.type.rawValue, forKey: "folderSortType")
        UserDefaults.standard.set(option.ascending, forKey: "folderSortAscending")
    }
    
    func setLayout(_ layout: Layout) {
        self.layout = layout
        UserDefaults.standard.set(layout.rawValue, forKey: "layout")
    }
}

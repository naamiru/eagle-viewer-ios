//
//  EventCenter.swift
//  EagleViewer
//
//  Created on 2025/08/25
//

import Combine
import SwiftUI

enum AppEvent {
    case libraryWillChange(oldValue: Library?, newValue: Library?)
    case folderSortChanged(_ folder: Folder)
    case globalSortChanged
    case importProgressChanged
    case folderCacheInvalidated
    case navigationWillReset
}

class EventCenter: ObservableObject {
    static let shared = EventCenter()

    private init() {}

    // MARK: App Events

    let publisher = PassthroughSubject<AppEvent, Never>()

    func post(_ event: AppEvent) {
        publisher.send(event)
    }
}

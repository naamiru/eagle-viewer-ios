import SwiftUI

enum NavigationDestination: Hashable {
    // folder detail
    case folder(Folder.ID)
    // collections
    case all
    case uncategorized
    case random
}

@MainActor
final class NavigationManager: ObservableObject {
    @Published var path: [NavigationDestination] = []

    func popToRoot() {
        path.removeAll()
    }
}

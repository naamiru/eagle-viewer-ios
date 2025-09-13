import Combine
import SwiftUI

enum NavigationDestination: Hashable, Codable {
    // folder detail
    case folder(Folder.ID)
    // collections
    case all
    case uncategorized
    case random

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "folder":
            let folderID = try container.decode(Folder.ID.self, forKey: .value)
            self = .folder(folderID)
        case "all":
            self = .all
        case "uncategorized":
            self = .uncategorized
        case "random":
            self = .random
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .folder(let folderID):
            try container.encode("folder", forKey: .type)
            try container.encode(folderID, forKey: .value)
        case .all:
            try container.encode("all", forKey: .type)
        case .uncategorized:
            try container.encode("uncategorized", forKey: .type)
        case .random:
            try container.encode("random", forKey: .type)
        }
    }
}

@MainActor
final class NavigationManager: ObservableObject {
    @Published var path: [NavigationDestination] = []
    private var cancellable: AnyCancellable?

    private var settingsManager: SettingsManager {
        return SettingsManager.shared
    }

    init() {
        // TODO: validate folderID
        path = settingsManager.getNavigationPath()

        cancellable = $path
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] newPath in
                self?.settingsManager.setNavigationPath(newPath)
            }
    }

    func popToRoot() {
        path.removeAll()
    }
}

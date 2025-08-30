//
//  Layout.swift
//  EagleViewer
//
//  Created on 2025/08/27
//

import Foundation

enum Layout: String, CaseIterable {
    case col3 = "col3"
    case col4 = "col4"
    case col6 = "col6"
    
    func columnCount(isPortrait: Bool) -> Int {
        let baseCount = switch self {
        case .col3:
            3
        case .col4:
            4
        case .col6:
            6
        }
        return isPortrait ? baseCount : baseCount * 2
    }
    
    static let defaultValue: Layout = .col3
}
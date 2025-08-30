//
//  Logger+App.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let sql = Logger(subsystem: subsystem, category: "sql")
    static let app = Logger(subsystem: subsystem, category: "app")
}

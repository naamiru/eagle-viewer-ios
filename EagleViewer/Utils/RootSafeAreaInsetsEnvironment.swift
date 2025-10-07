//
//  RootSafeAreaInsetsEnvironment.swift
//  EagleViewer
//
//  Created on 2025/08/27
//

import SwiftUI

private struct RootSafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue: EdgeInsets = EdgeInsets()
}

extension EnvironmentValues {
    var rootSafeAreaInsets: EdgeInsets {
        get { self[RootSafeAreaInsetsKey.self] }
        set { self[RootSafeAreaInsetsKey.self] = newValue }
    }
}

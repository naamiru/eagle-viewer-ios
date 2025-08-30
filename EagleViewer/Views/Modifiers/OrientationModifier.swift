//
//  OrientationModifier.swift
//  EagleViewer
//
//  Created on 2025/08/27
//

import SwiftUI
import Combine

private struct IsPortraitKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isPortrait: Bool {
        get { self[IsPortraitKey.self] }
        set { self[IsPortraitKey.self] = newValue }
    }
}

struct OrientationModifier: ViewModifier {
    @State private var isPortrait = UIDevice.current.orientation.isPortrait || !UIDevice.current.orientation.isLandscape
    
    func body(content: Content) -> some View {
        content
            .environment(\.isPortrait, isPortrait)
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                let orientation = UIDevice.current.orientation
                // Only update if we have a valid orientation (not face up/down or unknown)
                if orientation.isPortrait || orientation.isLandscape {
                    isPortrait = orientation.isPortrait
                }
            }
    }
}

extension View {
    func detectOrientation() -> some View {
        modifier(OrientationModifier())
    }
}
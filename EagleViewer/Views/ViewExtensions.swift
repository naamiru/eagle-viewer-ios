//
//  ViewExtensions.swift
//  EagleViewer
//
//  Created on 2025/08/20
//

import SwiftUI

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
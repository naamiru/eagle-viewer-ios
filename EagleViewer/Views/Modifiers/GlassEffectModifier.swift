//
//  GlassEffectModifier.swift
//  EagleViewer
//
//  Created on 2025/02/14
//

import SwiftUI

struct RegularGlassEffectModifier: ViewModifier {
    let interactive: Bool
    @GestureState private var isPressed = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive())
            } else {
                content.glassEffect(.regular)
            }
        } else {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            let baseColor = Color(.systemGray6)
            let pressedColor = Color(white: 0.96)

            if interactive {
                content
                    .background(shape.fill(isPressed ? pressedColor : baseColor))
                    .animation(.easeInOut(duration: 0.15), value: isPressed)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .updating($isPressed) { _, state, _ in
                                state = true
                            }
                    )
            } else {
                content
                    .background(shape.fill(baseColor))
            }
        }
    }
}

extension View {
    func regularGlassEffect(interactive: Bool) -> some View {
        modifier(RegularGlassEffectModifier(interactive: interactive))
    }
}

struct GlassBackgroundModifier: ViewModifier {
    let shape: any Shape

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

extension View {
    func glassBackground(in shape: some Shape) -> some View {
        modifier(GlassBackgroundModifier(shape: shape))
    }
}

struct GlassProminentButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    func glassProminentButton() -> some View {
        modifier(GlassProminentButtonModifier())
    }
}

struct LegacyAccentForegroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.foregroundColor(.primary)
        } else {
            content.foregroundColor(.accentColor)
        }
    }
}

extension View {
    func legacyAccentForeground() -> some View {
        modifier(LegacyAccentForegroundModifier())
    }
}

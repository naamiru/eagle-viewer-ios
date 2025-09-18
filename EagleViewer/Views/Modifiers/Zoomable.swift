// Original source: https://github.com/ryohey/Zoomable
// Copyright (c) 2023 ryohey
// Licensed under MIT License
// https://github.com/ryohey/Zoomable/blob/main/LICENSE

import SwiftUI

struct ZoomableModifier: ViewModifier {
    let minZoomScale: CGFloat
    let doubleTapZoomScale: CGFloat

    let isSelected: Bool
    @Binding var isNoUI: Bool
    let onScaleChanged: (CGFloat) -> Void

    @State private var lastTransform: CGAffineTransform = .identity
    @State private var transform: CGAffineTransform = .identity
    @State private var contentSize: CGSize = .zero

    @State private var wasNoUIBeforeZoom = false

    private var isZooming: Bool {
        transform != .identity
    }

    func body(content: Content) -> some View {
        content
            .background(alignment: .topLeading) {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            contentSize = proxy.size
                        }
                }
            }
            .animatableTransformEffect(transform)
            .gesture(dragGesture, including: transform == .identity ? .none : .all)
            .gesture(magnificationGesture)
            .gesture(doubleTapGesture)
            .onTapGesture {
                if !isZooming {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNoUI.toggle()
                        wasNoUIBeforeZoom = isNoUI
                    }
                }
            }
            .onChange(of: transform) {
                if isSelected {
                    onScaleChanged(transform.scaleX)
                }

                if isZooming && !isNoUI {
                    wasNoUIBeforeZoom = false
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isNoUI = true
                    }
                } else if !isZooming && isNoUI && !wasNoUIBeforeZoom {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isNoUI = false
                    }
                }
            }
            .onAppear {
                if isSelected {
                    onScaleChanged(transform.scaleX)
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                let newTransform = CGAffineTransform.anchoredScale(
                    scale: value.magnification,
                    anchor: value.startAnchor.scaledBy(contentSize)
                )

                withAnimation(.interactiveSpring) {
                    transform = lastTransform.concatenating(newTransform)
                }
            }
            .onEnded { _ in
                onEndGesture()
            }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let newTransform: CGAffineTransform =
                    if transform.isIdentity {
                        .anchoredScale(scale: doubleTapZoomScale, anchor: value.location)
                    } else {
                        .identity
                    }

                withAnimation(.easeInOut(duration: 0.25)) {
                    transform = newTransform
                    lastTransform = newTransform
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                withAnimation(.interactiveSpring) {
                    transform = lastTransform.translatedBy(
                        x: value.translation.width / transform.scaleX,
                        y: value.translation.height / transform.scaleY
                    )
                }
            }
            .onEnded { _ in
                onEndGesture()
            }
    }

    private func onEndGesture() {
        let newTransform = limitTransform(transform)

        withAnimation(.snappy(duration: 0.1)) {
            transform = newTransform
            lastTransform = newTransform
        }
    }

    private func limitTransform(_ transform: CGAffineTransform) -> CGAffineTransform {
        let scaleX = transform.scaleX
        let scaleY = transform.scaleY

        if scaleX < minZoomScale
            || scaleY < minZoomScale
        {
            return .identity
        }

        let maxX = contentSize.width * (scaleX - 1)
        let maxY = contentSize.height * (scaleY - 1)

        if transform.tx > 0
            || transform.tx < -maxX
            || transform.ty > 0
            || transform.ty < -maxY
        {
            let tx = min(max(transform.tx, -maxX), 0)
            let ty = min(max(transform.ty, -maxY), 0)
            var transform = transform
            transform.tx = tx
            transform.ty = ty
            return transform
        }

        return transform
    }
}

extension View {
    @ViewBuilder
    func zoomable(
        isSelected: Bool,
        isNoUI: Binding<Bool>,
        onScaleChanged: @escaping (CGFloat) -> Void
    ) -> some View {
        let outOfBoundsColor: Color = isNoUI.wrappedValue ? .black : .clear
        ZStack {
            outOfBoundsColor
            self.modifier(ZoomableModifier(
                minZoomScale: 1,
                doubleTapZoomScale: 2,
                isSelected: isSelected,
                isNoUI: isNoUI,
                onScaleChanged: onScaleChanged
            ))
        }
    }
}

private extension View {
    @ViewBuilder
    func animatableTransformEffect(_ transform: CGAffineTransform) -> some View {
        scaleEffect(
            x: transform.scaleX,
            y: transform.scaleY,
            anchor: .zero
        )
        .offset(x: transform.tx, y: transform.ty)
    }
}

private extension UnitPoint {
    func scaledBy(_ size: CGSize) -> CGPoint {
        .init(
            x: x * size.width,
            y: y * size.height
        )
    }
}

private extension CGAffineTransform {
    static func anchoredScale(scale: CGFloat, anchor: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -anchor.x, y: -anchor.y)
    }

    var scaleX: CGFloat {
        sqrt(a * a + c * c)
    }

    var scaleY: CGFloat {
        sqrt(b * b + d * d)
    }
}

//
//  AnimatedImageView.swift
//  EagleViewer
//
//  Created on 2025/09/25
//

import SDWebImage
import SwiftUI

private final class AnimatedImageContainer: SDAnimatedImageView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

/// UIKit wrapper around SDAnimatedImageView
struct AnimatedImageView: UIViewRepresentable {
    let url: URL
    let contentMode: UIView.ContentMode
    let shouldAnimate: Bool

    func makeUIView(context: Context) -> SDAnimatedImageView {
        let v = AnimatedImageContainer()
        v.contentMode = contentMode
        v.clipsToBounds = true
        v.isUserInteractionEnabled = true
        v.isMultipleTouchEnabled = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        return v
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateUIView(_ uiView: SDAnimatedImageView, context: Context) {
        let coordinator = context.coordinator
        let urlChanged = coordinator.url != url
        let shouldRestart = shouldAnimate && (!coordinator.shouldAnimate || urlChanged)

        if urlChanged || shouldRestart {
            coordinator.url = url
            coordinator.shouldAnimate = shouldAnimate
            coordinator.isAnimating = false
            uiView.sd_setImage(with: url) { _, _, _, _ in
                if coordinator.shouldAnimate {
                    uiView.startAnimating()
                    coordinator.isAnimating = true
                } else {
                    uiView.stopAnimating()
                    coordinator.isAnimating = false
                }
            }
        } else {
            coordinator.shouldAnimate = shouldAnimate
            if shouldAnimate {
                if !coordinator.isAnimating, uiView.image != nil {
                    uiView.startAnimating()
                    coordinator.isAnimating = true
                }
            } else if coordinator.isAnimating {
                uiView.stopAnimating()
                coordinator.isAnimating = false
            }
        }
    }

    final class Coordinator {
        var url: URL?
        var isAnimating = false
        var shouldAnimate = false
    }
}

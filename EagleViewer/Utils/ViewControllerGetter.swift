//
//  ViewControllerGetter.swift
//  EagleViewer
//
//  Created on 2025/09/27
//

import SwiftUI

enum ViewControllerGetter {
    static func getRootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = scene.windows.first?.rootViewController
        else {
            return nil
        }
        return getVisibleViewController(from: rootViewController)
    }

    private static func getVisibleViewController(from vc: UIViewController) -> UIViewController {
        if let nav = vc as? UINavigationController {
            return getVisibleViewController(from: nav.visibleViewController!)
        }
        if let tab = vc as? UITabBarController {
            return getVisibleViewController(from: tab.selectedViewController!)
        }
        if let presented = vc.presentedViewController {
            return getVisibleViewController(from: presented)
        }
        return vc
    }
}

//
//  GoogleAuthManager.swift
//  EagleViewer
//
//  Created on 2025/09/27
//

import GoogleSignIn
import UIKit

enum GoogleAuthError: Error {
    case noPresentingViewController
}

enum GoogleAuthManager {
    static let requiredScopes: Set<String> = ["https://www.googleapis.com/auth/drive.readonly"]

    @MainActor
    static func ensureSignedIn() async throws -> GIDGoogleUser {
        guard let presenting = ViewControllerGetter.getRootViewController() else {
            throw GoogleAuthError.noPresentingViewController
        }

        let user = try await acquireUser(presenting: presenting)
        return try await postSignInHousekeeping(user: user, presenting: presenting)
    }

    @MainActor
    private static func acquireUser(presenting: UIViewController) async throws -> GIDGoogleUser {
        if let current = GIDSignIn.sharedInstance.currentUser {
            return current
        }
        if let restored = try? await restorePreviousSignIn() {
            return restored
        }
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenting,
            hint: nil,
            additionalScopes: Array(requiredScopes)
        )
        return result.user
    }

    @MainActor
    private static func postSignInHousekeeping(user: GIDGoogleUser, presenting: UIViewController) async throws -> GIDGoogleUser {
        // ensure scope
        let granted = Set(user.grantedScopes ?? [])
        let missing = requiredScopes.subtracting(granted)
        if !missing.isEmpty {
            try await user.addScopes(Array(missing), presenting: presenting)
        }

        // refresh token if needed
        let target = GIDSignIn.sharedInstance.currentUser ?? user
        try await target.refreshTokensIfNeeded()

        // currentUser may be updated after addScopes
        return GIDSignIn.sharedInstance.currentUser ?? target
    }

    private static func restorePreviousSignIn() async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { cont in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let user { cont.resume(returning: user) }
                else { cont.resume(throwing: error ?? NSError(domain: "GoogleAuth", code: -1)) }
            }
        }
    }

    static func isSignedIn() async -> Bool {
        if GIDSignIn.sharedInstance.currentUser != nil {
            return true
        }
        return await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user != nil)
            }
        }
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }
}

//
//  OneDriveAuthManager.swift
//  EagleViewer
//
//  Created on 2025/10/01
//

import AuthenticationServices
import CryptoKit
import Foundation
import OSLog
import UIKit

enum OneDriveAuthError: LocalizedError {
    case noPresentingViewController
    case authFailed(String)
    case tokenExchangeFailed(String)
    case noRefreshToken
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "Cannot present sign-in screen"
        case .authFailed(let message):
            return "Authentication failed: \(message)"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .noRefreshToken:
            return "No refresh token available. Please sign in again."
        case .notSignedIn:
            return "Not signed in to OneDrive"
        }
    }
}

enum OneDriveAuthManager {
    // MARK: - Configuration

    // Placeholder client ID — user must register an Azure AD app and replace this
    static let clientID = Bundle.main.object(forInfoDictionaryKey: "OneDriveClientID") as? String ?? ""
    static let redirectURI = "msauth.\(Bundle.main.bundleIdentifier ?? "")://auth"
    static let scopes = "Files.Read Files.Read.All offline_access"
    static let tenant = "consumers" // Personal Microsoft accounts only

    private static let authorizeURL = "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/authorize"
    private static let tokenURL = "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/token"

    // Keychain keys
    private static let keychainServiceAccessToken = "com.eagleviewer.onedrive.accessToken"
    private static let keychainServiceRefreshToken = "com.eagleviewer.onedrive.refreshToken"
    private static let keychainServiceExpiration = "com.eagleviewer.onedrive.expiration"

    // In-memory cache
    private static var cachedAccessToken: String?
    private static var cachedExpiration: Date?

    // Retain active session to prevent deallocation during auth flow
    private static var activeSession: ASWebAuthenticationSession?

    // MARK: - Public API

    /// Returns a valid access token, refreshing if needed, or prompting sign-in if no session exists.
    @MainActor
    static func ensureSignedIn() async throws -> String {
        // Try cached token
        if let token = cachedAccessToken, let exp = cachedExpiration, exp > Date().addingTimeInterval(60) {
            return token
        }

        // Try stored token
        if let token = keychainRead(service: keychainServiceAccessToken),
           let expStr = keychainRead(service: keychainServiceExpiration),
           let expInterval = TimeInterval(expStr)
        {
            let expDate = Date(timeIntervalSince1970: expInterval)
            if expDate > Date().addingTimeInterval(60) {
                cachedAccessToken = token
                cachedExpiration = expDate
                return token
            }
        }

        // Try refresh
        if let refreshToken = keychainRead(service: keychainServiceRefreshToken) {
            do {
                let token = try await refreshAccessToken(refreshToken)
                return token
            } catch {
                Logger.app.warning("OneDrive token refresh failed, will re-authenticate: \(error)")
            }
        }

        // Full sign-in
        return try await performSignIn()
    }

    static func isSignedIn() -> Bool {
        // Check for refresh token existence as the durable indicator
        return keychainRead(service: keychainServiceRefreshToken) != nil
    }

    static func signOut() {
        cachedAccessToken = nil
        cachedExpiration = nil
        keychainDelete(service: keychainServiceAccessToken)
        keychainDelete(service: keychainServiceRefreshToken)
        keychainDelete(service: keychainServiceExpiration)
    }

    // MARK: - OAuth Flow

    @MainActor
    private static func performSignIn() async throws -> String {
        guard let presenting = ViewControllerGetter.getRootViewController() else {
            throw OneDriveAuthError.noPresentingViewController
        }

        // Generate PKCE pair
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = UUID().uuidString

        // Build authorization URL
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]

        guard let authURL = components.url else {
            throw OneDriveAuthError.authFailed("Invalid authorization URL")
        }

        // Extract callback scheme from redirect URI
        let callbackScheme = redirectURI.components(separatedBy: "://").first ?? ""

        // Present ASWebAuthenticationSession
        // Hold references to prevent deallocation during auth flow
        let contextProvider = PresentationContextProvider(anchor: presenting.view.window!)
        let callbackURL: URL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    cont.resume(throwing: OneDriveAuthError.authFailed(error.localizedDescription))
                    return
                }
                guard let callbackURL else {
                    cont.resume(throwing: OneDriveAuthError.authFailed("No callback URL received"))
                    return
                }
                cont.resume(returning: callbackURL)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = contextProvider
            activeSession = session
            session.start()
        }
        activeSession = nil

        // Extract authorization code
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            let errorDesc = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error_description" })?.value
            throw OneDriveAuthError.authFailed(errorDesc ?? "No authorization code in callback")
        }

        // Verify state
        let returnedState = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            throw OneDriveAuthError.authFailed("State mismatch — possible CSRF attack")
        }

        // Exchange code for tokens
        return try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
    }

    private static func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientID,
            "code": code,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
            "scope": scopes,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OneDriveAuthError.tokenExchangeFailed(errorBody)
        }

        return try processTokenResponse(data)
    }

    private static func refreshAccessToken(_ refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
            "scope": scopes,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Refresh failed — clear tokens so next call triggers full sign-in
            signOut()
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OneDriveAuthError.tokenExchangeFailed(errorBody)
        }

        return try processTokenResponse(data)
    }

    private static func processTokenResponse(_ data: Data) throws -> String {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        let expiration = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

        // Store tokens
        keychainWrite(service: keychainServiceAccessToken, data: tokenResponse.access_token)
        keychainWrite(service: keychainServiceExpiration, data: String(expiration.timeIntervalSince1970))

        if let refreshToken = tokenResponse.refresh_token {
            keychainWrite(service: keychainServiceRefreshToken, data: refreshToken)
        }

        // Cache
        cachedAccessToken = tokenResponse.access_token
        cachedExpiration = expiration

        return tokenResponse.access_token
    }

    // MARK: - PKCE

    private static func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Keychain Helpers

    private static func keychainWrite(service: String, data: String) {
        let dataBytes = Data(data.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "onedrive",
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = dataBytes
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func keychainRead(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "onedrive",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "onedrive",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASWebAuthenticationSession Presentation Context

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

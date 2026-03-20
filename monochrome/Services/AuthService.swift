import Foundation
import Combine
import AuthenticationServices
import UIKit

class AuthService: ObservableObject {
    static let shared = AuthService()

    private let endpoint = "https://auth.monochrome.tf/v1"
    private let projectId = "auth-for-monochrome"

    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let sessionKey = "monochrome_auth_session"

    // Dedicated URLSession that persists Appwrite session cookies
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = .shared
        return URLSession(configuration: config)
    }()

    var isAuthenticated: Bool { currentUser != nil }

    init() {
        restoreSession()
    }

    // MARK: - Sign In with Email/Password

    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let url = URL(string: "\(endpoint)/account/sessions/email")!
        let body: [String: Any] = ["email": email, "password": password]

        let _: AppwriteSession = try await appwriteRequest(url: url, method: "POST", body: body)
        try await fetchCurrentUser()
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let createURL = URL(string: "\(endpoint)/account")!
        let createBody: [String: Any] = ["userId": "unique()", "email": email, "password": password]

        let _: AppwriteAccount = try await appwriteRequest(url: createURL, method: "POST", body: createBody)

        // Create session after account creation
        let sessionURL = URL(string: "\(endpoint)/account/sessions/email")!
        let sessionBody: [String: Any] = ["email": email, "password": password]

        let _: AppwriteSession = try await appwriteRequest(url: sessionURL, method: "POST", body: sessionBody)
        try await fetchCurrentUser()
    }

    // MARK: - Google OAuth

    func signInWithGoogle() async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Appwrite expects the callback scheme to be: appwrite-callback-{projectId}
        let callbackScheme = "appwrite-callback-\(projectId)"
        let successURL = "\(callbackScheme)://auth/callback"
        let failureURL = "\(callbackScheme)://auth/failure"

        guard let encodedSuccess = successURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedFailure = failureURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let oauthURL = URL(string: "\(endpoint)/account/tokens/oauth2/google?project=\(projectId)&success=\(encodedSuccess)&failure=\(encodedFailure)") else {
            throw AuthError.serverError("Invalid OAuth URL")
        }

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: oauthURL, callbackURLScheme: callbackScheme) { url, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthError.serverError(error.localizedDescription))
                    }
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: AuthError.serverError("No callback URL received"))
                    return
                }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false

            DispatchQueue.main.async {
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let window = scene.windows.first,
                      let rootVC = window.rootViewController else {
                    continuation.resume(throwing: AuthError.serverError("No window available"))
                    return
                }

                let provider = OAuthPresentationContextProvider(anchor: window)
                session.presentationContextProvider = provider
                // Retain session and provider until completion
                objc_setAssociatedObject(rootVC, "oauthSession", session, .OBJC_ASSOCIATION_RETAIN)
                objc_setAssociatedObject(rootVC, "oauthProvider", provider, .OBJC_ASSOCIATION_RETAIN)
                session.start()
            }
        }

        // Extract userId and secret from callback URL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let userId = components.queryItems?.first(where: { $0.name == "userId" })?.value,
              let secret = components.queryItems?.first(where: { $0.name == "secret" })?.value else {
            throw AuthError.serverError("Missing OAuth credentials in callback")
        }

        // Create session with the OAuth token
        let sessionURL = URL(string: "\(endpoint)/account/sessions/token")!
        let sessionBody: [String: Any] = ["userId": userId, "secret": secret]

        let _: AppwriteSession = try await appwriteRequest(url: sessionURL, method: "POST", body: sessionBody)
        try await fetchCurrentUser()
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let url = URL(string: "\(endpoint)/account/recovery")!
        let body: [String: Any] = ["email": email, "url": "https://monochrome.tf/reset-password"]

        let _: AppwriteRecovery = try await appwriteRequest(url: url, method: "POST", body: body)
    }

    // MARK: - Sign Out

    func signOut() async {
        if let url = URL(string: "\(endpoint)/account/sessions/current") {
            let _ = try? await appwriteRequest(url: url, method: "DELETE") as AppwriteEmpty
        }

        // Clear cookies for the Appwrite domain
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: endpoint)!) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        currentUser = nil
        defaults.removeObject(forKey: sessionKey)
    }

    // MARK: - Fetch Current User

    @discardableResult
    func fetchCurrentUser() async throws -> AuthUser {
        let url = URL(string: "\(endpoint)/account")!
        let account: AppwriteAccount = try await appwriteRequest(url: url, method: "GET")

        let user = AuthUser(
            uid: account.id,
            email: account.email,
            name: account.name.isEmpty ? nil : account.name
        )
        currentUser = user
        saveSession(user)
        return user
    }

    // MARK: - Session Persistence

    private func saveSession(_ user: AuthUser) {
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    private func restoreSession() {
        guard let data = defaults.data(forKey: sessionKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else { return }

        currentUser = user

        // Verify session is still valid
        Task {
            do {
                try await fetchCurrentUser()
            } catch {
                await signOut()
            }
        }
    }

    // MARK: - Appwrite REST API

    private func appwriteRequest<T: Decodable>(url: URL, method: String, body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(projectId, forHTTPHeaderField: "X-Appwrite-Project")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }

        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? JSONDecoder().decode(AppwriteErrorResponse.self, from: data) {
                throw AuthError.serverError(mapAppwriteError(errorResponse.message, type: errorResponse.type))
            }
            throw AuthError.networkError
        }

        // Handle empty responses (DELETE)
        if data.isEmpty || httpResponse.statusCode == 204 {
            if let empty = AppwriteEmpty() as? T {
                return empty
            }
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func mapAppwriteError(_ message: String, type: String?) -> String {
        switch type {
        case "user_invalid_credentials": return "Incorrect email or password."
        case "user_not_found": return "No account found with this email."
        case "user_already_exists": return "An account already exists with this email."
        case "user_blocked": return "This account has been disabled."
        case "password_recently_used": return "This password was recently used. Choose a different one."
        case "password_personal_data": return "Password should not contain personal data."
        case "user_password_mismatch": return "Incorrect password."
        case "general_rate_limit_exceeded": return "Too many attempts. Please try again later."
        default: return message
        }
    }
}

// MARK: - OAuth Presentation Context Provider

private class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

// MARK: - Models

struct AuthUser: Codable {
    let uid: String
    let email: String
    let name: String?
}

enum AuthError: LocalizedError {
    case serverError(String)
    case networkError
    case cancelled

    var errorDescription: String? {
        switch self {
        case .serverError(let message): return message
        case .networkError: return "Network error. Please check your connection."
        case .cancelled: return nil
        }
    }
}

// MARK: - Appwrite REST API Response Models

private struct AppwriteAccount: Decodable {
    let id: String
    let email: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "$id"
        case email, name
    }
}

private struct AppwriteSession: Decodable {
    let id: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case id = "$id"
        case userId
    }
}

private struct AppwriteRecovery: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "$id"
    }
}

struct AppwriteEmpty: Decodable {
    init() {}
}

private struct AppwriteErrorResponse: Decodable {
    let message: String
    let type: String?
}

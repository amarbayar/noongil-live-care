import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth

/// Firebase Auth wrapper with Sign in with Apple support.
@MainActor
final class AuthService: ObservableObject {

    // MARK: - Published State

    @Published var currentUser: FirebaseAuth.User?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?

    // MARK: - Private

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    // MARK: - Init

    init() {
        listenForAuthChanges()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth State Listener

    private func listenForAuthChanges() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }

    // MARK: - Sign in with Apple

    /// Creates the ASAuthorizationAppleIDRequest configured for Firebase.
    /// Call this from your ASAuthorizationController setup.
    func createAppleIDRequest() -> ASAuthorizationAppleIDRequest {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        return request
    }

    /// Handles the ASAuthorization result from Sign in with Apple.
    func handleAppleSignIn(_ authorization: ASAuthorization) async {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            error = "Invalid credential type"
            return
        }

        guard let nonce = currentNonce else {
            error = "No nonce available. Call createAppleIDRequest() first."
            return
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            error = "Unable to get identity token"
            return
        }

        isLoading = true
        error = nil

        do {
            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            let result = try await Auth.auth().signIn(with: credential)
            currentUser = result.user
            isAuthenticated = true
            print("[AuthService] Signed in: \(result.user.uid)")
        } catch {
            self.error = error.localizedDescription
            print("[AuthService] Sign in failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            isAuthenticated = false
            print("[AuthService] Signed out")
        } catch {
            self.error = error.localizedDescription
            print("[AuthService] Sign out failed: \(error)")
        }
    }

    // MARK: - Delete Account

    func deleteAccount(consentService: ConsentService? = nil) async {
        guard let user = Auth.auth().currentUser else {
            error = "No user signed in"
            return
        }

        isLoading = true
        error = nil

        do {
            // 1. Delete server-side data first (Firestore + Neo4j)
            let token = try await user.getIDToken()
            let url = URL(string: "\(Config.backendBaseURL)/api/users/me")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw NSError(domain: "AuthService", code: httpResponse.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "Backend deletion failed"])
            }

            // 2. Clear local consent
            consentService?.revokeAll()

            // 3. Clear local UserDefaults consent keys
            let consentKeys = ["consent_healthData", "consent_aiAnalysis", "consent_voiceProcessing",
                               "consent_terms", "consent_privacy", "consent_age"]
            for key in consentKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }

            // 4. Delete Firebase Auth last (point of no return)
            try await user.delete()
            currentUser = nil
            isAuthenticated = false
            print("[AuthService] Account deleted (cascading)")
        } catch {
            self.error = error.localizedDescription
            print("[AuthService] Account deletion failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Nonce Helpers

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

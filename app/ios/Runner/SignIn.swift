import AuthenticationServices
import CryptoKit
import UIKit

/// Signing in on the iPhone, natively: Sign in with Apple through
/// AuthenticationServices, and Google through its OAuth page in the system's
/// secure browser sheet (code flow with PKCE, the iOS client id from Google
/// Cloud Console). Either way the result is the provider's ID token, which
/// the Glyf server checks before it issues a session.
///
/// Results are plain dictionaries for the bridge: `idToken` (plus `name` and
/// `email` when Apple shares them) on success, `error` otherwise, where
/// "cancelled" means the person closed the sheet.
final class SignIn: NSObject {
    static let shared = SignIn()

    private var appleDone: (([String: Any]) -> Void)?
    private var appleController: ASAuthorizationController?
    private var webSession: ASWebAuthenticationSession?

    // MARK: Sign in with Apple

    func apple(nonce: String, done: @escaping ([String: Any]) -> Void) {
        appleDone?(["error": "cancelled"])
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        // Apple puts this hash in the token; the server hashes the raw nonce
        // and compares, so a token can't be replayed into another sign-in.
        request.nonce = Self.sha256Hex(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        appleDone = done
        appleController = controller
        controller.performRequests()
    }

    private func finishApple(_ result: [String: Any]) {
        let done = appleDone
        appleDone = nil
        appleController = nil
        done?(result)
    }

    // MARK: Google

    private static let googleAuthURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let googleTokenURL = "https://oauth2.googleapis.com/token"

    func google(clientId: String, nonce: String, done: @escaping ([String: Any]) -> Void) {
        // "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc",
        // the redirect scheme Google gives every iOS client.
        let scheme = clientId.split(separator: ".").reversed().joined(separator: ".")
        guard clientId.hasSuffix(".apps.googleusercontent.com"), !scheme.isEmpty else {
            done(["error": "not_configured"])
            return
        }
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = Self.randomString(bytes: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(bytes: 16)

        var components = URLComponents(string: Self.googleAuthURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let url = components.url else {
            done(["error": "not_configured"])
            return
        }
        webSession?.cancel()
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
            self?.webSession = nil
            if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                done(["error": "cancelled"])
                return
            }
            guard let callback,
                  let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
                done(["error": error?.localizedDescription ?? "failed"])
                return
            }
            func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if let problem = item("error") {
                done(["error": problem == "access_denied" ? "cancelled" : problem])
                return
            }
            guard item("state") == state, let code = item("code") else {
                done(["error": "failed"])
                return
            }
            Self.exchange(code: code, clientId: clientId, redirect: redirect, verifier: verifier, done: done)
        }
        session.presentationContextProvider = self
        // Share Safari's Google session, so someone signed in there picks an
        // account instead of typing a password.
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        if !session.start() {
            webSession = nil
            done(["error": "failed"])
        }
    }

    /// The code from Google's page, traded for tokens. An iOS client proves
    /// itself with the PKCE verifier; there is no client secret on a phone.
    private static func exchange(code: String, clientId: String, redirect: String, verifier: String,
                                 done: @escaping ([String: Any]) -> Void) {
        var request = URLRequest(url: URL(string: googleTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "code": code, "client_id": clientId, "redirect_uri": redirect,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ]
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, error in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                if let token = json?["id_token"] as? String {
                    done(["idToken": token])
                } else if error != nil {
                    done(["error": "network"])
                } else {
                    done(["error": (json?["error"] as? String) ?? "failed"])
                }
            }
        }.resume()
    }

    // MARK: Helpers

    private static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomString(bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64URL
    }
}

extension SignIn: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            finishApple(["error": "failed"])
            return
        }
        var result: [String: Any] = ["idToken": token]
        // Apple shares the name only the first time someone signs in.
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { result["name"] = name }
        if let email = credential.email { result["email"] = email }
        finishApple(result)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code = (error as? ASAuthorizationError)?.code
        switch code {
        case .canceled: finishApple(["error": "cancelled"])
        // No Apple Account on the device, or the capability is missing.
        case .unknown, .notHandled: finishApple(["error": "apple_unavailable"])
        default: finishApple(["error": error.localizedDescription])
        }
    }
}

extension SignIn: ASAuthorizationControllerPresentationContextProviding,
                  ASWebAuthenticationPresentationContextProviding {
    private var window: ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { window }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}

/// The Glyf session, in this app's Keychain (never the shared group: the
/// keyboard has no use for it).
enum SessionKeychain {
    private static let service = "so.glyf.session"
    private static let account = "session-v1"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ json: String) -> Bool {
        clear()
        var query = base
        query[kSecValueData as String] = Data(json.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

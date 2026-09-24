import AuthenticationServices
import CryptoKit
import UIKit

/// Signing in on the iPhone, natively: Sign in with Apple through
/// AuthenticationServices, and Google through its OAuth page in the system's
/// secure browser sheet (code flow with PKCE, the iOS client id from Google
/// Cloud Console). Either way the result is the provider's ID token, which
/// the Glyf server checks before it issues a session. Google also grants
/// Calendar and Meet, kept for the keyboard in GoogleAccess.
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
    private static let googleRevokeURL = "https://oauth2.googleapis.com/revoke"

    /// Signing in with Google also asks for Google Calendar and Meet, so the
    /// keyboard can add events (Google emails the guests) and make Meet
    /// links. Google shows them as boxes the person can untick. Until Google
    /// verifies the app for these scopes, its consent page warns that the
    /// app is unverified; false here asks only in Connected tools.
    static let askCalendarAtSignIn = true

    func google(clientId: String, nonce: String, done: @escaping ([String: Any]) -> Void) {
        let scope = (["openid", "email", "profile"]
            + (Self.askCalendarAtSignIn ? GoogleAccess.scopes : [])).joined(separator: " ")
        authorizeGoogle(clientId: clientId, scope: scope, nonce: nonce, loginHint: nil,
                        prompt: "select_account") { json, error in
            guard let json else { return done(["error": error ?? "failed"]) }
            guard let token = json["id_token"] as? String else { return done(["error": "failed"]) }
            Self.keepGrant(json, clientId: clientId)
            done(["idToken": token])
        }
    }

    /// Connected tools' Connect: Calendar and Meet on its own, for someone
    /// who signed in with Apple, or who unticked them at sign-in.
    func connectGoogle(clientId: String, loginHint: String?, done: @escaping ([String: Any]) -> Void) {
        let scope = (["openid", "email"] + GoogleAccess.scopes).joined(separator: " ")
        authorizeGoogle(clientId: clientId, scope: scope, nonce: nil, loginHint: loginHint,
                        prompt: "consent") { json, error in
            guard let json else { return done(["error": error ?? "failed"]) }
            guard Self.keepGrant(json, clientId: clientId) else { return done(["error": "not_granted"]) }
            done(Self.googleStatus())
        }
    }

    /// Takes the grant back from Google too, not just off the phone.
    func disconnectGoogle(done: @escaping () -> Void) {
        let grant = GoogleAccess.load()
        GoogleAccess.clear()
        guard let grant, grant.apiBase == nil,
              var components = URLComponents(string: Self.googleRevokeURL) else { return done() }
        components.queryItems = [URLQueryItem(name: "token", value: grant.refreshToken)]
        guard let url = components.url else { return done() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async { done() }
        }.resume()
    }

    /// What Connected tools shows: connected or not, as whom, and what for.
    static func googleStatus() -> [String: Any] {
        guard let grant = GoogleAccess.load() else { return ["connected": false] }
        var out: [String: Any] = [
            "connected": true,
            "calendar": grant.scopes.contains(GoogleAccess.calendarScope),
            "meet": grant.scopes.contains(GoogleAccess.meetScope),
        ]
        if let email = grant.email { out["email"] = email }
        return out
    }

    /// Keeps what Google granted for the keyboard, when it granted Calendar
    /// or Meet. True when it did.
    @discardableResult
    private static func keepGrant(_ json: [String: Any], clientId: String) -> Bool {
        let scopes = GoogleAccess.granted(json["scope"] as? String)
        guard !scopes.isEmpty, let refresh = json["refresh_token"] as? String, !refresh.isEmpty else {
            return false
        }
        let email = (json["id_token"] as? String).flatMap(Self.claims)?["email"] as? String
        return GoogleAccess.save(GoogleGrant(refreshToken: refresh, clientId: clientId, scopes: scopes,
                                             email: email ?? GoogleAccess.load()?.email))
    }

    /// The claims of a JWT, unchecked: only the email is read, for display.
    private static func claims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Google's OAuth page in the secure browser sheet, then the code traded
    /// for tokens. The token response, or why there isn't one.
    private func authorizeGoogle(clientId: String, scope: String, nonce: String?, loginHint: String?,
                                 prompt: String, done: @escaping ([String: Any]?, String?) -> Void) {
        // "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc",
        // the redirect scheme Google gives every iOS client.
        let scheme = clientId.split(separator: ".").reversed().joined(separator: ".")
        guard clientId.hasSuffix(".apps.googleusercontent.com"), !scheme.isEmpty else {
            done(nil, "not_configured")
            return
        }
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = Self.randomString(bytes: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(bytes: 16)

        var components = URLComponents(string: Self.googleAuthURL)!
        var items = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: prompt),
            // Whatever was granted before stays granted.
            URLQueryItem(name: "include_granted_scopes", value: "true"),
        ]
        if let nonce { items.append(URLQueryItem(name: "nonce", value: nonce)) }
        if let loginHint, !loginHint.isEmpty { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components.queryItems = items
        guard let url = components.url else {
            done(nil, "not_configured")
            return
        }
        webSession?.cancel()
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
            self?.webSession = nil
            if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                done(nil, "cancelled")
                return
            }
            guard let callback,
                  let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
                done(nil, error?.localizedDescription ?? "failed")
                return
            }
            func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if let problem = item("error") {
                done(nil, problem == "access_denied" ? "cancelled" : problem)
                return
            }
            guard item("state") == state, let code = item("code") else {
                done(nil, "failed")
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
            done(nil, "failed")
        }
    }

    /// The code from Google's page, traded for tokens. An iOS client proves
    /// itself with the PKCE verifier; there is no client secret on a phone.
    private static func exchange(code: String, clientId: String, redirect: String, verifier: String,
                                 done: @escaping ([String: Any]?, String?) -> Void) {
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
                if let json, json["access_token"] != nil || json["id_token"] != nil {
                    done(json, nil)
                } else if error != nil {
                    done(nil, "network")
                } else {
                    done(nil, (json?["error"] as? String) ?? "failed")
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

/// The Glyf session. It lives in the shared keychain group (GlyfSession) so
/// the keyboard can send it too — the server wants it on every call.
enum SessionKeychain {
    static func load() -> String? { GlyfSession.loadJSON() }

    @discardableResult
    static func save(_ json: String) -> Bool { GlyfSession.save(json) }

    static func clear() { GlyfSession.clear() }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

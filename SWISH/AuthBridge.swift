import Foundation
import WebKit
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import FacebookCore
import FacebookLogin

// MARK: - Auth configuration
//
// Placeholder IDs: when the Facebook app is created, replace
// FACEBOOK_APP_ID_PLACEHOLDER and FACEBOOK_CLIENT_TOKEN_PLACEHOLDER here AND
// in Info.plist (FacebookAppID, FacebookClientToken, and the fb<APP_ID> URL
// scheme). Google needs no constant: the client ID comes from
// GoogleService-Info.plist via FirebaseApp options, and the REVERSED_CLIENT_ID
// URL scheme in Info.plist must be replaced with the REVERSED_CLIENT_ID from
// the re-downloaded GoogleService-Info.plist once the Google provider is
// enabled in the Firebase console.
enum AuthConfig {
    static let facebookAppID = "FACEBOOK_APP_ID_PLACEHOLDER"
    static let facebookClientToken = "FACEBOOK_CLIENT_TOKEN_PLACEHOLDER"
}

/// One-time SDK setup, called from SWISHApp.init after FirebaseApp.configure().
enum AuthSDK {
    static func configure() {
        // Google: client ID comes from the Firebase config.
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        // Facebook: settings come from Info.plist (FacebookAppID etc.).
        ApplicationDelegate.shared.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
    }

    static func handleOpenURL(_ url: URL) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) { return true }
        return ApplicationDelegate.shared.application(
            UIApplication.shared, open: url,
            sourceApplication: nil, annotation: [UIApplication.OpenURLOptionsKey.annotation])
    }
}

/// JS -> native accounts bridge. Web code calls:
///   window.webkit.messageHandlers.auth.postMessage({action: "state"})
///   window.webkit.messageHandlers.auth.postMessage({action: "signIn", provider: "google"|"facebook"|"apple"})
///   window.webkit.messageHandlers.auth.postMessage({action: "unlink", provider: ...})
///   window.webkit.messageHandlers.auth.postMessage({action: "checkUsername", name: ...})
///   window.webkit.messageHandlers.auth.postMessage({action: "claimUsername", name: ...})
///   window.webkit.messageHandlers.auth.postMessage({action: "addFriend", name: ...})
///   window.webkit.messageHandlers.auth.postMessage({action: "listFriends"})
///   window.webkit.messageHandlers.auth.postMessage({action: "deleteAccount"})
///
/// Every player has a Firebase Anonymous Auth identity created automatically
/// on first run; the claimed username binds to that uid. Connecting a
/// provider LINKS it to the same account (never creates a second account),
/// so the username and progress survive a phone change.
///
/// Results are pushed to the page via window.onAuthResult(jsonString):
///   state: {type:"state", ok, uid, isAnonymous, username, name, email,
///           photoURL, linkedProviders:["google"|"facebook"|"apple"]}
///   ops:   {type:"op", op, ok, ...} or {type:"op", op, ok:false, error, code?}
final class AuthBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    private var appleNonce: String?
    private var appleController: ASAuthorizationController?

    override init() {
        super.init()
        // Invisible plumbing: make sure a Firebase user exists.
        ensureUser { _ in }
    }

    // MARK: Message handling

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "auth",
              let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }
        switch action {
        case "state":
            pushState()
        case "signIn":
            signIn(provider: dict["provider"] as? String ?? "")
        case "unlink":
            unlink(provider: dict["provider"] as? String ?? "")
        case "checkUsername":
            checkUsername(name: dict["name"] as? String ?? "")
        case "claimUsername":
            claimUsername(name: dict["name"] as? String ?? "")
        case "addFriend":
            addFriend(name: dict["name"] as? String ?? "")
        case "listFriends":
            listFriends()
        case "deleteAccount":
            deleteAccount()
        default:
            break
        }
    }

    // MARK: Result plumbing

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = "window.onAuthResult && window.onAuthResult('\(escaped)')"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func opError(_ op: String, _ message: String, code: String? = nil) {
        var payload: [String: Any] = ["type": "op", "op": op, "ok": false, "error": message]
        if let code = code { payload["code"] = code }
        send(payload)
    }

    private func providerKey(_ providerID: String) -> String? {
        switch providerID {
        case "google.com": return "google"
        case "facebook.com": return "facebook"
        case "apple.com": return "apple"
        default: return nil
        }
    }

    private func linkedProviders(_ user: User) -> [String] {
        user.providerData.compactMap { providerKey($0.providerID) }
    }

    /// Push the full account state. The username lives in Firestore
    /// users/{uid}; if Firestore is unreachable we still push the auth
    /// state with an empty username rather than failing.
    private func pushState() {
        ensureUser { [weak self] user in
            guard let self = self, let user = user else {
                self?.send(["type": "state", "ok": false, "error": "No account yet."])
                return
            }
            let base: [String: Any] = [
                "type": "state", "ok": true,
                "uid": user.uid,
                "isAnonymous": user.isAnonymous,
                "name": user.displayName ?? "",
                "email": user.email ?? "",
                "photoURL": user.photoURL?.absoluteString ?? "",
                "linkedProviders": self.linkedProviders(user),
            ]
            Firestore.firestore().collection("users").document(user.uid).getDocument { snap, _ in
                var payload = base
                payload["username"] = (snap?.data()?["username"] as? String) ?? ""
                self.send(payload)
                // First sign-in state is known: the moment to set up
                // push (permission + registration + token). PushManager
                // guards itself, so later state pushes only retry the
                // token write.
                PushManager.shared.begin()
            }
        }
    }

    /// Guarantee a Firebase user exists (anonymous on first run).
    private func ensureUser(_ completion: @escaping (User?) -> Void) {
        if let user = Auth.auth().currentUser {
            completion(user)
            return
        }
        Auth.auth().signInAnonymously { result, _ in
            completion(result?.user)
        }
    }

    // MARK: Provider sign-in (link to the current account)

    private func signIn(provider: String) {
        switch provider {
        case "google": signInGoogle()
        case "facebook": signInFacebook()
        case "apple": signInApple()
        default: opError("signIn", "Unknown provider.")
        }
    }

    private func signInGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            opError("signIn", "Google sign-in isn't switched on yet.", code: "unconfigured")
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let vc = topViewController() else {
            opError("signIn", "Couldn't open Google sign-in.")
            return
        }
        GIDSignIn.sharedInstance.signIn(withPresenting: vc) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                self.opError("signIn", (error as NSError).localizedDescription)
                return
            }
            guard let idToken = result?.user.idToken?.tokenString else {
                self.opError("signIn", "Google didn't return a sign-in token.")
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result?.user.accessToken.tokenString ?? "")
            self.finishLink(credential: credential, provider: "google")
        }
    }

    private func signInFacebook() {
        guard AuthConfig.facebookAppID != "FACEBOOK_APP_ID_PLACEHOLDER" else {
            opError("signIn", "Facebook sign-in isn't switched on yet.", code: "unconfigured")
            return
        }
        guard let vc = topViewController() else {
            opError("signIn", "Couldn't open Facebook sign-in.")
            return
        }
        let manager = LoginManager()
        manager.logIn(permissions: ["public_profile", "email"], from: vc) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                self.opError("signIn", (error as NSError).localizedDescription)
                return
            }
            if result?.isCancelled == true {
                self.opError("signIn", "Facebook sign-in was cancelled.")
                return
            }
            guard let token = AccessToken.current?.tokenString else {
                self.opError("signIn", "Facebook didn't return a sign-in token.")
                return
            }
            let credential = FacebookAuthProvider.credential(withAccessToken: token)
            self.finishLink(credential: credential, provider: "facebook")
        }
    }

    private func signInApple() {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        appleController = controller
        controller.performRequests()
    }

    /// Link a provider credential to the CURRENT (anonymous) account so the
    /// username and progress are kept. A credential that already belongs to
    /// a different account is a clean error — never a silent account switch.
    private func finishLink(credential: AuthCredential, provider: String) {
        ensureUser { [weak self] user in
            guard let self = self, let user = user else {
                self?.opError("signIn", "No account yet — try again in a moment.")
                return
            }
            if self.linkedProviders(user).contains(provider) {
                self.send(["type": "op", "op": "signIn", "ok": true, "provider": provider,
                           "linkedProviders": self.linkedProviders(user)])
                self.pushState()
                return
            }
            user.link(with: credential) { _, error in
                if let error = error {
                    let ns = error as NSError
                    // 17007 email already in use, 17025 credential already in
                    // use, 17057 credential already linked to another user.
                    if ns.domain == AuthErrorDomain &&
                        [17007, 17025, 17057].contains(ns.code) {
                        self.opError("signIn",
                                     "That account is already linked to another player.",
                                     code: "already-linked")
                    } else {
                        self.opError("signIn", ns.localizedDescription)
                    }
                    return
                }
                self.send(["type": "op", "op": "signIn", "ok": true, "provider": provider,
                           "linkedProviders": self.linkedProviders(Auth.auth().currentUser ?? user)])
                self.pushState()
            }
        }
    }

    private func unlink(provider: String) {
        guard let user = Auth.auth().currentUser else {
            opError("unlink", "No account yet.")
            return
        }
        let providerID: String
        switch provider {
        case "google": providerID = "google.com"
        case "facebook": providerID = "facebook.com"
        case "apple": providerID = "apple.com"
        default:
            opError("unlink", "Unknown provider.")
            return
        }
        user.unlink(fromProvider: providerID) { [weak self] _, error in
            guard let self = self else { return }
            if let error = error {
                self.opError("unlink", (error as NSError).localizedDescription)
                return
            }
            self.send(["type": "op", "op": "unlink", "ok": true, "provider": provider,
                       "linkedProviders": self.linkedProviders(Auth.auth().currentUser ?? user)])
            self.pushState()
        }
    }

    // MARK: Usernames

    static func validUsername(_ name: String) -> Bool {
        let pattern = "^[A-Za-z0-9_]{3,16}$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    private func checkUsername(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validUsername(trimmed) else {
            send(["type": "op", "op": "checkUsername", "ok": true, "name": trimmed,
                  "available": false, "invalid": true])
            return
        }
        Firestore.firestore().collection("usernames")
            .document(trimmed.lowercased()).getDocument { [weak self] snap, error in
                guard let self = self else { return }
                if let error = error {
                    self.opError("checkUsername",
                                 "Couldn't check that name right now. (\(error.localizedDescription))")
                    return
                }
                self.send(["type": "op", "op": "checkUsername", "ok": true,
                           "name": trimmed, "available": !(snap?.exists ?? false)])
            }
    }

    private func claimUsername(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validUsername(trimmed) else {
            opError("claimUsername",
                    "Usernames are 3–16 characters: letters, numbers, underscore.",
                    code: "invalid")
            return
        }
        ensureUser { [weak self] user in
            guard let self = self, let user = user else {
                self?.opError("claimUsername", "No account yet — try again in a moment.")
                return
            }
            let db = Firestore.firestore()
            let claimRef = db.collection("usernames").document(trimmed.lowercased())
            let userRef = db.collection("users").document(user.uid)
            // Internal result codes: 0 ok, 1 taken, 2 already has a username.
            db.runTransaction({ transaction, errorPointer -> Any? in
                let claimSnap: DocumentSnapshot
                let userSnap: DocumentSnapshot
                do {
                    claimSnap = try transaction.getDocument(claimRef)
                    userSnap = try transaction.getDocument(userRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
                if claimSnap.exists {
                    if (claimSnap.data()?["uid"] as? String) == user.uid {
                        return 0 // already mine — idempotent success
                    }
                    return 1
                }
                let existing = (userSnap.data()?["username"] as? String) ?? ""
                if !existing.isEmpty { return 2 }
                transaction.setData(["uid": user.uid], forDocument: claimRef)
                var userData: [String: Any] = [
                    "uid": user.uid,
                    "username": trimmed,
                    "provider": user.isAnonymous ? "anonymous" : (self.linkedProviders(user).first ?? ""),
                    "updatedAt": FieldValue.serverTimestamp(),
                ]
                if !userSnap.exists {
                    userData["wins"] = 0
                    userData["losses"] = 0
                    userData["draws"] = 0
                    userData["createdAt"] = FieldValue.serverTimestamp()
                }
                transaction.setData(userData, forDocument: userRef, merge: true)
                return 0
            }, completion: { result, error in
                if let error = error {
                    self.opError("claimUsername",
                                 "Couldn't claim that name right now. (\(error.localizedDescription))")
                    return
                }
                let code = (result as? Int) ?? 0
                if code == 1 {
                    self.opError("claimUsername", "That username is taken.", code: "taken")
                } else if code == 2 {
                    self.opError("claimUsername", "You already have a username.", code: "has-username")
                } else {
                    self.send(["type": "op", "op": "claimUsername", "ok": true,
                               "username": trimmed, "uid": user.uid])
                    self.pushState()
                }
            })
        }
    }

    // MARK: Friends by username

    private func addFriend(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            opError("addFriend", "Type a username first.", code: "invalid")
            return
        }
        ensureUser { [weak self] user in
            guard let self = self, let user = user else {
                self?.opError("addFriend", "No account yet — try again in a moment.")
                return
            }
            let db = Firestore.firestore()
            db.collection("usernames").document(trimmed.lowercased())
                .getDocument { [weak self] snap, error in
                    guard let self = self else { return }
                    if let error = error {
                        self.opError("addFriend",
                                     "Couldn't look that up right now. (\(error.localizedDescription))")
                        return
                    }
                    guard let snap = snap, snap.exists,
                          let friendUid = snap.data()?["uid"] as? String else {
                        self.opError("addFriend", "No player named \(trimmed) yet.", code: "not-found")
                        return
                    }
                    if friendUid == user.uid {
                        self.opError("addFriend", "That's your own username.", code: "invalid")
                        return
                    }
                    db.collection("users").document(user.uid)
                        .collection("friends").document(friendUid)
                        .setData(["username": trimmed, "addedAt": FieldValue.serverTimestamp()]) { error in
                            if let error = error {
                                self.opError("addFriend",
                                             "Couldn't add that friend right now. (\(error.localizedDescription))")
                                return
                            }
                            self.send(["type": "op", "op": "addFriend", "ok": true,
                                       "friend": ["username": trimmed, "uid": friendUid]])
                        }
                }
        }
    }

    private func listFriends() {
        ensureUser { [weak self] user in
            guard let self = self, let user = user else {
                self?.opError("listFriends", "No account yet.")
                return
            }
            Firestore.firestore().collection("users").document(user.uid)
                .collection("friends").getDocuments { [weak self] snap, error in
                    guard let self = self else { return }
                    if let error = error {
                        self.opError("listFriends",
                                     "Couldn't load friends right now. (\(error.localizedDescription))")
                        return
                    }
                    let friends = (snap?.documents ?? []).map { doc in
                        ["username": (doc.data()["username"] as? String) ?? doc.documentID,
                         "uid": doc.documentID]
                    }
                    self.send(["type": "op", "op": "listFriends", "ok": true, "friends": friends])
                }
        }
    }

    // MARK: Account deletion

    /// Permanently delete the signed-in account (Apple Guideline
    /// 5.1.1(v)). Order matters: the Firestore data goes first, in one
    /// atomic batch — the profile doc users/{uid}, every doc in its
    /// friends subcollection, the usernames/{name} claim, and the
    /// player's own matchmaking / splitmatch tickets — and the Firebase
    /// Auth user is deleted last. Deleting auth first would orphan the
    /// data under a uid nobody can ever sign in as again (the username
    /// would stay taken forever); deleting data first leaves a clean,
    /// retryable state if the auth delete is refused.
    ///
    /// Firebase refuses user deletion when the last sign-in is too old:
    /// that answers with code "requires-recent-login" so the web layer
    /// can tell the player to sign in again (Google/Apple link, which
    /// refreshes the session) and retry — the retry is safe because
    /// every Firestore delete here is idempotent.
    ///
    /// Other players' friend lists keep a stale entry for this uid
    /// (friends are docs keyed by uid with no uid field to query by,
    /// so there is no cheap client-side sweep); the entry points at a
    /// profile that no longer exists and listFriends renders it as a
    /// name with no account behind it.
    ///
    /// NOTE: client-side deletion of users/{uid} and usernames/{name}
    /// needs the matching firestore.rules change (owner delete) to be
    /// deployed; until then the batch commit fails with
    /// PERMISSION_DENIED and this op answers with that error, intact.
    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else {
            opError("deleteAccount", "No account to delete.", code: "no-user")
            return
        }
        let uid = user.uid
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(uid)
        userRef.getDocument { [weak self] snap, _ in
            guard let self = self else { return }
            let username = (snap?.data()?["username"] as? String) ?? ""
            userRef.collection("friends").getDocuments { [weak self] friendsSnap, _ in
                guard let self = self else { return }
                let batch = db.batch()
                for doc in friendsSnap?.documents ?? [] {
                    batch.deleteDocument(doc.reference)
                }
                batch.deleteDocument(db.collection("matchmaking").document(uid))
                batch.deleteDocument(db.collection("splitmatch").document(uid))
                batch.deleteDocument(userRef)
                if !username.isEmpty {
                    batch.deleteDocument(db.collection("usernames").document(username.lowercased()))
                }
                batch.commit { [weak self] error in
                    guard let self = self else { return }
                    if let error = error {
                        self.opError("deleteAccount",
                                     "Couldn't delete your account data right now. (\(error.localizedDescription))")
                        return
                    }
                    user.delete { [weak self] error in
                        guard let self = self else { return }
                        if let error = error {
                            let ns = error as NSError
                            // 17014 = FIRAuthErrorCodeRequiresRecentLogin:
                            // the last sign-in is too old for a destructive
                            // op. The data batch above is already gone and
                            // every step is idempotent, so a fresh sign-in
                            // + retry finishes the job.
                            if ns.domain == AuthErrorDomain && ns.code == 17014 {
                                self.opError("deleteAccount",
                                             "Sign-in needs to be fresh for deletion.",
                                             code: "requires-recent-login")
                            } else {
                                self.opError("deleteAccount", ns.localizedDescription)
                            }
                            return
                        }
                        self.send(["type": "op", "op": "deleteAccount", "ok": true])
                    }
                }
            }
        }
    }

    // MARK: Apple nonce helpers

    static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        for b in bytes {
            result.append(charset[Int(b) % charset.count])
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Apple sign-in delegate

extension AuthBridge: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = appleNonce else {
            opError("signIn", "Apple sign-in didn't return a token.")
            return
        }
        let oauth = OAuthProvider.credential(withProviderID: "apple.com",
                                             idToken: idToken, rawNonce: nonce)
        finishLink(credential: oauth, provider: "apple")
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            opError("signIn", "Apple sign-in was cancelled.")
        } else {
            opError("signIn", (error as NSError).localizedDescription)
        }
    }
}

extension AuthBridge: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return topViewController()?.view.window ?? ASPresentationAnchor()
    }
}

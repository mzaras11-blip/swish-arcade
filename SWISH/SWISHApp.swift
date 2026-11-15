import SwiftUI
import WebKit
import StoreKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications
import AVFoundation
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// JS -> native haptics bridge. Web code can call:
///   window.webkit.messageHandlers.haptics.postMessage("light" | "medium" | "heavy"
///       | "success" | "warning" | "error" | "selection")
final class HapticsBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "haptics" else { return }
        let style = (message.body as? String) ?? "light"
        DispatchQueue.main.async {
            switch style {
            case "heavy":
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case "medium":
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case "success":
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "warning":
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case "error":
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case "selection":
                UISelectionFeedbackGenerator().selectionChanged()
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

/// JS -> native review-prompt bridge. The web build calls this only after a
/// WON game (gated web-side: never after a loss, never in the first session):
///   window.webkit.messageHandlers.review.postMessage("promptAfterWin")
/// Note: SKStoreReviewController never displays in TestFlight builds; it
/// becomes active in App Store builds. Apple's own throttling still applies.
final class ReviewBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "review" else { return }
        guard (message.body as? String) == "promptAfterWin" else { return }
        DispatchQueue.main.async {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview()
            }
        }
    }
}

/// JS -> native audio bridge for background music. Web Audio is unreliable in
/// WKWebView, so the web build delegates music to this when available:
///   window.webkit.messageHandlers.audio.postMessage({action: "play"})
///   window.webkit.messageHandlers.audio.postMessage({action: "stop"})
///   window.webkit.messageHandlers.audio.postMessage({action: "volume", value: 0.5})
final class NativeAudioBridge: NSObject, WKScriptMessageHandler {
    private var player: AVAudioPlayer?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "audio",
              let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }
        DispatchQueue.main.async { [weak self] in
            switch action {
            case "play": self?.play()
            case "stop": self?.player?.stop()
            case "volume":
                if let v = dict["value"] as? Double { self?.player?.volume = Float(v) }
            default: break
            }
        }
    }

    private func play() {
        if let p = player, p.isPlaying { return }
        guard let url = Bundle.main.url(forResource: "music", withExtension: "wav",
                                        subdirectory: "web") else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1  // loop forever
            p.volume = 0.5
            p.play()
            player = p
        } catch { /* silent fail — web audio fallback covers it */ }
    }
}

/// JS -> native ads bridge. Web code calls:
///   window.webkit.messageHandlers.ads.postMessage({action: "showRewarded", reward: "hint"})
///   window.webkit.messageHandlers.ads.postMessage({action: "showInterstitial"})
///   window.webkit.messageHandlers.ads.postMessage({action: "showBanner"})
///   window.webkit.messageHandlers.ads.postMessage({action: "hideBanner"})
///
/// For rewarded ads, native calls back via: webView.evaluateJavaScript("onAdReward('hint')")
final class AdsBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    /// Called when banner visibility should change (web controls this).
    var onBannerVisibility: ((Bool) -> Void)?

    /// Last time an interstitial slot actually fired. Interstitials are
    /// offered after EVERY finished game, but never more than once per
    /// 180 seconds, and never mid-game / mid-turn.
    private var lastInterstitialAt: Date?
    /// Interstitial slots fired so far. Every 4th slot is a house promo
    /// (S.W.I.S.H promoting itself, rendered by the web layer via
    /// Ads.housePromo()) instead of an AdMob interstitial — the cadence
    /// lives here so it can never stack on top of a real interstitial.
    private var interstitialSlots = 0

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "ads",
              let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }
        DispatchQueue.main.async { [weak self] in
            switch action {
            case "showRewarded":
                let reward = dict["reward"] as? String ?? "hint"
                self?.showRewarded(reward: reward)
            case "showInterstitial":
                self?.maybeShowInterstitial()
            case "showBanner":
                self?.onBannerVisibility?(true)
            case "hideBanner":
                self?.onBannerVisibility?(false)
            case "gameFinished":
                self?.interstitialSlot()
            case "storeState":
                self?.reportStoreState()
            default: break
            }
        }
    }

    private func showRewarded(reward: String) {
        // Skip ads if user purchased Remove Ads.
        if StoreManager.shared.hasRemoveAds { notifyReward(reward); return }
        guard let vc = topViewController() else { notifyReward(reward); return }
        AdManager.shared.showRewarded(from: vc) { [weak self] earned in
            if earned { self?.notifyReward(reward) }
        }
    }

    private func notifyReward(_ reward: String) {
        let js = "if(window.onAdReward)window.onAdReward('\(reward)')"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func maybeShowInterstitial() {
        interstitialSlot()
    }

    /// One interstitial opportunity. Remove Ads owners never see one.
    /// Enforces the 180-second minimum gap between interstitials. Every
    /// 4th slot shows a house promo instead of an AdMob interstitial;
    /// a house promo counts as the slot (the gap restarts from it).
    private func interstitialSlot() {
        if StoreManager.shared.hasRemoveAds { return }
        if let last = lastInterstitialAt, Date().timeIntervalSince(last) < 180 { return }
        lastInterstitialAt = Date()
        interstitialSlots += 1
        if interstitialSlots % 4 == 0 {
            notifyHousePromo()
        } else {
            showInterstitial()
        }
    }

    /// Tell the web layer to show its full-screen house promo.
    private func notifyHousePromo() {
        let js = "if(window.Ads&&Ads.housePromo)Ads.housePromo()"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Report purchase state the web layer can't see itself (Remove Ads
    /// ownership gates the Remove Ads house promo).
    private func reportStoreState() {
        let owned = StoreManager.shared.hasRemoveAds
        let js = "if(window.onAdsState)window.onAdsState('{\"removeAds\":\(owned)}')"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func showInterstitial() {
        if StoreManager.shared.hasRemoveAds { return }
        guard let vc = topViewController() else { return }
        AdManager.shared.showInterstitial(from: vc)
    }
}

/// JS -> native Split Screen (live friend game) bridge. Web code calls:
///   window.webkit.messageHandlers.live.postMessage({action: "create", name: "..."})
///   window.webkit.messageHandlers.live.postMessage({action: "join", code: "ABC123", name: "..."})
///   window.webkit.messageHandlers.live.postMessage({action: "send", event: "<json string>"})
///   window.webkit.messageHandlers.live.postMessage({action: "leave"})
/// Native calls back via window.SwishLive._onRoom / _onPeer / _onEvent / _onError,
/// each with one string argument (JSON for room/peer/event, plain text for errors).
/// Rooms live in Firestore: rooms/{code} plus rooms/{code}/events, where each
/// event document is {from, body, seq, ts}. Events are forwarded to the other
/// player in (ts, seq) order, exactly once.
final class LiveBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private var roomRef: DocumentReference?
    private var eventsListener: ListenerRegistration?
    private var roomListener: ListenerRegistration?
    private var seq = 0
    private var forwarded = Set<String>()
    private var ticketRef: DocumentReference?
    private var ticketListener: ListenerRegistration?
    private var peerJoined = false
    private var myUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var db: Firestore { Firestore.firestore() }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }
        switch action {
        case "create":
            createRoom(name: dict["name"] as? String ?? "Player")
        case "join":
            joinRoom(code: (dict["code"] as? String ?? "").uppercased(),
                     name: dict["name"] as? String ?? "Player")
        case "send":
            if let event = dict["event"] as? String { sendEvent(event) }
        case "leave":
            leaveRoom()
        case "matchmake":
            matchmake(name: dict["name"] as? String ?? "Player",
                      gameType: dict["gameType"] as? String ?? "split")
        case "matchmakeCancel":
            matchmakeCancel()
        default:
            break
        }
    }

    private func writeRoom(code: String, name: String, completion: @escaping (Bool) -> Void) {
        db.collection("rooms").document(code).setData([
            "hostUid": myUID, "hostName": name, "state": "open",
            "created": FieldValue.serverTimestamp(),
        ]) { err in completion(err == nil) }
    }

    private func createRoom(name: String) {
        guard !myUID.isEmpty else {
            callError("Sign-in is not ready yet — try again in a moment.")
            return
        }
        peerJoined = false
        let code = Self.makeCode()
        writeRoom(code: code, name: name) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.callError("Could not create the room.")
                return
            }
            self.roomRef = self.db.collection("rooms").document(code)
            self.attach(code: code)
            self.callJSON("._onRoom", ["code": code])
        }
    }

    private func joinRoom(code: String, name: String) {
        peerJoined = false
        guard !myUID.isEmpty else {
            callError("Sign-in is not ready yet — try again in a moment.")
            return
        }
        guard code.count >= 4 else {
            callError("That room code looks too short.")
            return
        }
        let ref = db.collection("rooms").document(code)
        ref.getDocument { [weak self] snap, err in
            guard let self else { return }
            if let err {
                self.callError("Could not reach the room: \(err.localizedDescription)")
                return
            }
            guard let snap, snap.exists else {
                self.callError("Room \(code) was not found.")
                return
            }
            if (snap.data()?["state"] as? String) == "closed" {
                self.callError("That room is closed.")
                return
            }
            ref.updateData(["guestUid": self.myUID, "guestName": name, "state": "live"]) { err in
                if let err {
                    self.callError("Could not join the room: \(err.localizedDescription)")
                    return
                }
                self.roomRef = ref
                self.attach(code: code)
                self.callJSON("._onRoom", ["code": code])
                if let hostName = snap.data()?["hostName"] as? String {
                    self.callJSON("._onPeer", ["name": hostName])
                }
            }
        }
    }


    // MARK: Split Screen matchmaking (collection "splitmatch")
    //
    // Tickets are { uid, username, room, status, createdAt }. A searcher
    // first tries to claim the oldest fresh waiting ticket in a transaction
    // (the waiter pre-created their room, so the claimer just joins it);
    // otherwise the searcher creates a room and waits on their own ticket.

    // Game types (build 5): tickets carry a "gameType" ("split" or
    // "rush"); seekers only claim tickets of their own type. Tickets
    // written by older builds have no gameType and count as "split".

    private func matchmake(name: String, gameType: String) {
        guard !myUID.isEmpty else {
            callError("Sign-in is not ready yet — try again in a moment.")
            return
        }
        peerJoined = false
        db.collection("splitmatch")
            .whereField("status", isEqualTo: "waiting")
            .order(by: "createdAt")
            .limit(to: 5)
            .getDocuments { [weak self] snap, _ in
                guard let self else { return }
                let now = Date()
                let candidate = (snap?.documents ?? []).first { doc in
                    guard doc.documentID != self.myUID else { return false }
                    guard ((doc.data()["gameType"] as? String) ?? "split") == gameType else { return false }
                    guard let ts = doc.data()["createdAt"] as? Timestamp else { return false }
                    return ts.dateValue().timeIntervalSince(now) > -180
                }
                if let ticket = candidate {
                    self.claim(ticket: ticket, name: name, gameType: gameType)
                } else {
                    self.enqueue(name: name, gameType: gameType)
                }
            }
    }

    private func claim(ticket: QueryDocumentSnapshot, name: String, gameType: String) {
        let ref = ticket.reference
        let room = ticket.data()["room"] as? String ?? ""
        let hostName = ticket.data()["username"] as? String ?? "Player"
        let uid = myUID
        guard !room.isEmpty else { enqueue(name: name, gameType: gameType); return }
        db.runTransaction({ txn, _ -> Any? in
            let snap = try? txn.getDocument(ref)
            guard let data = snap?.data(), (data["status"] as? String) == "waiting" else { return nil }
            txn.updateData(["status": "matched", "partnerUid": uid, "partnerName": name],
                           forDocument: ref)
            return room as Any
        }, completion: { [weak self] result, err in
            guard let self else { return }
            if err != nil || (result as? String) == nil {
                self.enqueue(name: name, gameType: gameType)
                return
            }
            self.peerJoined = true
            self.roomRef = self.db.collection("rooms").document(room)
            self.attach(code: room)
            self.callJSON("._onRoom", ["code": room, "host": false])
            self.callJSON("._onPeer", ["name": hostName])
        })
    }

    private func enqueue(name: String, gameType: String) {
        let code = Self.makeCode()
        writeRoom(code: code, name: name) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.callError("Could not start matchmaking — try again.")
                return
            }
            let ticket = self.db.collection("splitmatch").document(self.myUID)
            self.ticketRef = ticket
            ticket.setData([
                "uid": self.myUID, "username": name, "room": code,
                "status": "waiting", "createdAt": FieldValue.serverTimestamp(),
                "gameType": gameType,
            ]) { err in
                if let err {
                    self.callError("Could not start matchmaking: \(err.localizedDescription)")
                    return
                }
                self.roomRef = self.db.collection("rooms").document(code)
                self.attach(code: code)
                self.callJSON("._onRoom", ["code": code, "host": true])
                self.ticketListener = ticket.addSnapshotListener { [weak self] snap, _ in
                    guard let self, let data = snap?.data() else { return }
                    if (data["status"] as? String) == "matched" {
                        self.peerJoined = true
                        if let partner = data["partnerName"] as? String {
                            self.callJSON("._onPeer", ["name": partner])
                        }
                        self.ticketListener?.remove()
                        self.ticketListener = nil
                        self.ticketRef?.delete()
                        self.ticketRef = nil
                    }
                }
            }
        }
    }

    private func matchmakeCancel() {
        ticketListener?.remove()
        ticketListener = nil
        ticketRef?.delete()
        ticketRef = nil
        if roomRef != nil && !peerJoined {
            detach()
            roomRef?.updateData(["state": "closed"])
            roomRef = nil
            forwarded.removeAll()
        }
    }

    private func attach(code: String) {
        detach()
        forwarded.removeAll()
        let ref = db.collection("rooms").document(code)
        roomListener = ref.addSnapshotListener { [weak self] snap, _ in
            guard let self, let data = snap?.data() else { return }
            let hostUid = data["hostUid"] as? String ?? ""
            if self.myUID == hostUid, let guest = data["guestName"] as? String {
                self.peerJoined = true
                self.callJSON("._onPeer", ["name": guest])
            } else if self.myUID != hostUid, let host = data["hostName"] as? String {
                self.callJSON("._onPeer", ["name": host])
            }
        }
        eventsListener = ref.collection("events").addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            // Forward in (server ts, sender seq) order, exactly once per event.
            let sorted = snap.documents.sorted { a, b in
                let ta = a.data()["ts"] as? Timestamp
                let tb = b.data()["ts"] as? Timestamp
                if let ta, let tb, ta != tb { return ta.compare(tb) == .orderedAscending }
                if (ta == nil) != (tb == nil) { return tb == nil }
                let sa = a.data()["seq"] as? Int ?? 0
                let sb = b.data()["seq"] as? Int ?? 0
                return sa < sb
            }
            for doc in sorted {
                let data = doc.data()
                if (data["ts"] as? Timestamp) == nil { continue } // wait for server ts
                if (data["from"] as? String) == self.myUID { continue }
                if self.forwarded.contains(doc.documentID) { continue }
                guard let body = data["body"] as? String else { continue }
                self.forwarded.insert(doc.documentID)
                self.callJS("._onEvent", body)
            }
        }
    }

    private func sendEvent(_ body: String) {
        guard let ref = roomRef else { return }
        seq += 1
        ref.collection("events").addDocument(data: [
            "from": myUID, "body": body, "seq": seq,
            "ts": FieldValue.serverTimestamp(),
        ])
    }

    private func leaveRoom() {
        ticketListener?.remove()
        ticketListener = nil
        ticketRef?.delete()
        ticketRef = nil
        peerJoined = false
        detach()
        roomRef?.updateData(["state": "closed"])
        roomRef = nil
        forwarded.removeAll()
    }

    private func detach() {
        eventsListener?.remove()
        roomListener?.remove()
        eventsListener = nil
        roomListener = nil
    }

    // MARK: Callbacks into the web layer (same escaping pattern as AuthBridge)

    private func callJS(_ fn: String, _ arg: String) {
        let escaped = arg
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = "window.SwishLive && window.SwishLive\(fn)('\(escaped)')"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func callJSON(_ fn: String, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        callJS(fn, json)
    }

    private func callError(_ message: String) {
        callJS("._onError", message)
    }

    private static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}

/// JS -> native online-presence bridge. Implements docs/presence-bridge.md:
///   window.webkit.messageHandlers.presence.postMessage({action: "heartbeat"})
///   window.webkit.messageHandlers.presence.postMessage({action: "friends"})
/// Heartbeat stamps users/{uid}.lastSeen with the server timestamp.
/// Friends reads my friend list, then each friend's profile, and replies
/// via window.onPresenceResult('<json string>') — the same single-string
/// callback shape AuthBridge uses:
///   {"type":"friends","friends":[{"name":"<username>","lastSeen":<epoch ms>}]}
final class PresenceBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private var db: Firestore { Firestore.firestore() }
    private var myUID: String { Auth.auth().currentUser?.uid ?? "" }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "presence",
              let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }
        switch action {
        case "heartbeat": stampLastSeen()
        case "friends": replyFriends()
        default: break
        }
    }

    /// Merge-write so the rest of the profile is untouched. If the
    /// profile doc does not exist yet (no username claimed) the rules
    /// deny the create and the stamp is simply skipped — presence only
    /// matters once a player has a username and friends.
    private func stampLastSeen() {
        guard !myUID.isEmpty else { return }
        db.collection("users").document(myUID)
            .setData(["lastSeen": FieldValue.serverTimestamp()], merge: true)
    }

    private func replyFriends() {
        guard !myUID.isEmpty else { return }
        let uid = myUID
        db.collection("users").document(uid).collection("friends")
            .getDocuments { [weak self] snap, _ in
                guard let self else { return }
                let docs = snap?.documents ?? []
                if docs.isEmpty {
                    self.sendFriends([])
                    return
                }
                var out: [[String: Any]] = []
                let group = DispatchGroup()
                for doc in docs {
                    let friendUid = doc.documentID
                    let fallback = (doc.data()["username"] as? String) ?? friendUid
                    group.enter()
                    self.db.collection("users").document(friendUid)
                        .getDocument { fsnap, _ in
                            let data = fsnap?.data()
                            let name = (data?["username"] as? String) ?? fallback
                            var ms = 0
                            if let ts = data?["lastSeen"] as? Timestamp {
                                ms = Int(ts.dateValue().timeIntervalSince1970 * 1000)
                            }
                            out.append(["name": name, "lastSeen": ms])
                            group.leave()
                        }
                }
                group.notify(queue: .main) { self.sendFriends(out) }
            }
    }

    private func sendFriends(_ friends: [[String: Any]]) {
        let payload: [String: Any] = ["type": "friends", "friends": friends]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = "window.onPresenceResult && window.onPresenceResult('\(escaped)')"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

/// JS -> native board sharing. Web code calls:
///   window.webkit.messageHandlers.share.postMessage(
///     {action: "shareBoard", image: "data:image/png;base64,..."})
/// The web layer renders the finished board to a PNG; native presents
/// the system share sheet with it.
final class ShareBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "share",
              let dict = message.body as? [String: Any] else { return }
        if (dict["action"] as? String) == "shareText" {
            let text = dict["text"] as? String ?? ""
            let url = dict["url"] as? String
            DispatchQueue.main.async { Self.presentShareSheet(text: text, url: url) }
            return
        }
        guard (dict["action"] as? String) == "shareBoard",
              let image = dict["image"] as? String else { return }
        DispatchQueue.main.async { Self.presentShareSheet(image: image) }
    }

    private static func presentShareSheet(text: String, url: String?) {
        var items: [Any] = []
        if !text.isEmpty { items.append(text) }
        if let url = url, let u = URL(string: url) { items.append(u) }
        guard !items.isEmpty, let vc = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: items,
                                             applicationActivities: nil)
        // iPad: the sheet needs an anchor or it crashes.
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = vc.view
            pop.sourceRect = CGRect(x: vc.view.bounds.midX,
                                    y: vc.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        vc.present(sheet, animated: true)
    }

    private static func presentShareSheet(image: String) {
        var b64 = image
        if let comma = b64.firstIndex(of: ",") {
            b64 = String(b64[b64.index(after: comma)...])
        }
        guard let data = Data(base64Encoded: b64),
              let uiImage = UIImage(data: data),
              let vc = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: [uiImage],
                                             applicationActivities: nil)
        // iPad: the sheet needs an anchor or it crashes.
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = vc.view
            pop.sourceRect = CGRect(x: vc.view.bounds.midX,
                                    y: vc.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        vc.present(sheet, animated: true)
    }
}

// MARK: - Push notifications (FCM)

/// "Your turn" pushes are sent by Cloud Functions (functions/index.js);
/// the shell's job is permission, APNs registration, and keeping this
/// device's FCM token on users/{uid}.fcmTokens.
///
/// Timing: begin() is called from AuthBridge.pushState — the first
/// sign-in state push — so permission is asked once the account exists,
/// never cold at first frame. Registration then follows the standard
/// FCM wiring: APNs device token -> Messaging.apnsToken (AppDelegate)
/// -> FCM registration token -> Firestore arrayUnion on the profile
/// (the same write the retired native UI used in FirebaseBackend).
final class PushManager: NSObject {
    static let shared = PushManager()
    private var began = false
    private var lastToken: String?

    func begin() {
        if !began {
            began = true
            Messaging.messaging().delegate = self
            UNUserNotificationCenter.current().delegate = self
            requestPermissionAndRegister()
        }
        flushToken()
    }

    private func requestPermissionAndRegister() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "swish.pushAsked") {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }
        defaults.set(true, forKey: "swish.pushAsked")
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
    }

    /// Write the freshest token we have to the signed-in profile.
    /// Retried on every state push, so a token that arrived before the
    /// profile doc existed still lands once it does.
    private func flushToken() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if let token = lastToken { store(token: token, uid: uid) }
        Messaging.messaging().token { [weak self] token, _ in
            guard let self, let token else { return }
            self.lastToken = token
            self.store(token: token, uid: uid)
        }
    }

    /// users/{uid}.fcmTokens += token. updateData (not a merge create):
    /// the profile doc exists for anyone with a username, and before
    /// that the write is a no-op by design — see flushToken retries.
    private func store(token: String, uid: String) {
        Firestore.firestore().collection("users").document(uid)
            .updateData(["fcmTokens": FieldValue.arrayUnion([token])])
    }

    func didRegisterAPNsToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

extension PushManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        lastToken = fcmToken
        if let uid = Auth.auth().currentUser?.uid {
            store(token: fcmToken, uid: uid)
        }
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    /// Show pushes as banners while the app is in the foreground too.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

/// Minimal app delegate: SwiftUI owns the UI; this exists so APNs
/// registration results reach Firebase Messaging. PushManager setup is
/// triggered from AuthBridge.pushState instead of here, which keeps it
/// strictly after FirebaseApp.configure() and the first sign-in state.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegisterAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Push is best-effort; the game never depends on it.
        print("APNs registration failed: \(error.localizedDescription)")
    }
}

/// Holds all JS bridges for the web view's lifetime.
final class WebCoordinator: NSObject {
    let haptics = HapticsBridge()
    let review = ReviewBridge()
    let audio = NativeAudioBridge()
    let ads = AdsBridge()
    let auth = AuthBridge()
    let live = LiveBridge()
    let presence = PresenceBridge()
    let share = ShareBridge()
}

/// Full-screen web view hosting the S.W.I.S.H web build bundled at web/index.html.
/// This is the entire app UI now — the native game screens are retired.
struct WebGameView: UIViewRepresentable {
    @Binding var showBanner: Bool

    func makeCoordinator() -> WebCoordinator { WebCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Let the web build's music/sound play without requiring a tap first.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator.haptics, name: "haptics")
        config.userContentController.add(context.coordinator.review, name: "review")
        config.userContentController.add(context.coordinator.audio, name: "audio")
        config.userContentController.add(context.coordinator.ads, name: "ads")
        config.userContentController.add(context.coordinator.auth, name: "auth")
        config.userContentController.add(context.coordinator.live, name: "live")
        config.userContentController.add(context.coordinator.presence, name: "presence")
        config.userContentController.add(context.coordinator.share, name: "share")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Wire the ads bridge back to this web view for reward callbacks.
        context.coordinator.ads.webView = webView
        // Same for the auth bridge (account state + op results).
        context.coordinator.auth.webView = webView
        // Same for the Split Screen live bridge (event callbacks).
        context.coordinator.live.webView = webView
        // Same for the presence bridge (friend last-seen replies).
        context.coordinator.presence.webView = webView
        context.coordinator.ads.onBannerVisibility = { [weak webView] visible in
            // Banner visibility is driven by SwiftUI state via the binding.
            // We post a notification; ContentView observes it.
            NotificationCenter.default.post(
                name: .adsBannerVisibility,
                object: nil,
                userInfo: ["visible": visible]
            )
            _ = webView // keep reference alive
        }

        if let url = Bundle.main.url(forResource: "index", withExtension: "html",
                                     subdirectory: "web") {
            // Bundled copy — works fully offline.
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let live = URL(string: "https://mzaras11-blip.github.io/swish-game/") {
            // Safety net if the bundled file ever goes missing.
            webView.load(URLRequest(url: live))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

extension Notification.Name {
    static let adsBannerVisibility = Notification.Name("swish.adsBannerVisibility")
}

/// Banner ad at the bottom of the screen. The web layer asks for the
/// banner on menu screens, but the strip is only rendered (and only
/// takes space) once a real ad has loaded — an empty slot must never
/// show as a blank strip or sit on top of the tab bar.
#if canImport(GoogleMobileAds)
struct AdBannerWrapper: View {
    @State private var requested = false
    @ObservedObject private var adManager = AdManager.shared

    private var onScreen: Bool {
        requested && adManager.bannerLoaded && !StoreManager.shared.hasRemoveAds
    }

    var body: some View {
        Group {
            if !StoreManager.shared.hasRemoveAds {
                BannerAdView()
                    .frame(height: onScreen ? 50 : 0)
                    .opacity(onScreen ? 1 : 0)
                    .allowsHitTesting(onScreen)
                    .clipped()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .adsBannerVisibility)) { note in
            if let v = note.userInfo?["visible"] as? Bool {
                withAnimation { requested = v }
            }
        }
    }
}
#else
struct AdBannerWrapper: View {
    var body: some View { EmptyView() }
}
#endif

/// Root layout. The web view fills the screen; while a real banner ad
/// is on screen the web view lifts by the banner's height so the ad
/// strip sits below the app content and never covers the tab bar. The
/// background is the app's own menu gradient, so no gap can ever show
/// the plain white window background (the build 3 loading-screen bug).
struct RootView: View {
    @State private var showBanner = false
    @State private var bannerRequested = false
    @ObservedObject private var adManager = AdManager.shared

    private var bannerOnScreen: Bool {
        bannerRequested && adManager.bannerLoaded && !StoreManager.shared.hasRemoveAds
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WebGameView(showBanner: $showBanner)
                .ignoresSafeArea()
                .padding(.bottom, bannerOnScreen ? 50 : 0)
                .animation(.easeInOut(duration: 0.25), value: bannerOnScreen)
            AdBannerWrapper()
        }
        .ignoresSafeArea(edges: .bottom)
        .background(
            LinearGradient(
                colors: [Color(red: 0.22, green: 0.32, blue: 0.95),
                         Color(red: 0.52, green: 0.28, blue: 0.92),
                         Color(red: 0.92, green: 0.32, blue: 0.58)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .onReceive(NotificationCenter.default.publisher(for: .adsBannerVisibility)) { note in
            if let v = note.userInfo?["visible"] as? Bool {
                bannerRequested = v
            }
        }
        .onAppear {
            // FCM "your turn" pushes: permission + APNs registration
            // are handled by PushManager after the first sign-in state
            // is known (see AuthBridge.pushState), not at cold launch.
            // Ask once for local-notification permission (daily play reminder).
            PlayReminder.shared.requestPermissionIfNeeded()
        }
        .onOpenURL { url in
            // Google / Facebook sign-in return URLs.
            _ = AuthSDK.handleOpenURL(url)
        }
    }
}

@main
struct SWISHApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Firebase backend for async multiplayer (Auth + Firestore +
        // Functions + Messaging). Config comes from the bundled
        // GoogleService-Info.plist.
        FirebaseApp.configure()
        // Social sign-in SDKs (Google / Facebook) — after Firebase so the
        // Google client ID can be read from the Firebase config.
        AuthSDK.configure()
        // Ads start only after the App Tracking Transparency decision
        // (Guideline 5.1.2(i), build 8): AdManager presents the ATT
        // request first, then starts the Google Mobile Ads SDK and
        // loads the first ads.
        AdManager.shared.beginAdFlow()
        // Give the web build's audio (music/SFX via Web Audio) a live
        // session to play through. Without this, WKWebView audio is silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Schedule the "come back" nudge; cleared on return or next game.
                PlayReminder.shared.schedule()
            } else if phase == .active {
                PlayReminder.shared.cancel()
            }
        }
    }
}

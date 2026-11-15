import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging


// MARK: - Firestore Codable bridge
//
// The Firebase SDK resolved by this project no longer ships the
// FirebaseFirestoreSwift module, so the snapshot data-mapping helpers and
// the Encodable setData variant are unavailable. This small bridge does the
// same job using only FirebaseFirestore: document <-> JSON <-> our Codable
// models. Dates round-trip as seconds-since-1970 doubles; Firestore
// Timestamps written by Cloud Functions decode the same way.

enum FirestoreCodable {
    static func decode<T: Decodable>(_ type: T.Type, from snapshot: DocumentSnapshot) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: jsonSafe(snapshot.data() ?? [:]))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(T.self, from: jsonData)
    }

    static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let jsonData = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]) ?? [:]
    }

    /// Recursively convert Firestore-native values (Timestamp, nested
    /// collections) into JSON-compatible ones.
    private static func jsonSafe(_ value: Any) -> Any {
        if let ts = value as? Timestamp {
            return ts.dateValue().timeIntervalSince1970
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues(jsonSafe)
        }
        if let array = value as? [Any] {
            return array.map(jsonSafe)
        }
        return value
    }
}

// MARK: - S.W.I.S.H async multiplayer: Firebase backend
//
// Server-authoritative implementation of MultiplayerBackend.
// Puzzles are dealt by Cloud Functions, racks are dealt per turn by the
// server, and every point is recomputed server-side on submitTurn.
// This class only *requests* actions; it never decides an outcome.
//
// Firestore layout (see multiplayer/DESIGN.md):
//   users/{uid}                      profile (stats are function-written only)
//   usernames/{lowercased}           { uid } — first writer wins
//   matchmaking/{uid}                ticket { uid, username, createdAt, status }
//   matches/{matchId}                match doc (function-written only)
//   matches/{matchId}/turns/{n}      turn audit trail (function-written only)
//   users/{uid}/challenges/{cid}     friend challenges (function-written only)

final class FirebaseBackend: MultiplayerBackend {

    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private var uid: String {
        get throws {
            guard let uid = auth.currentUser?.uid else { throw MPError.notSignedIn }
            return uid
        }
    }

    private func profileRef(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    // MARK: - Identity

    func signIn() async throws -> MPPlayerProfile {
        if auth.currentUser == nil {
            do {
                _ = try await auth.signInAnonymously()
            } catch {
                throw MPError.network(error)
            }
        }
        let uid = try self.uid
        let ref = profileRef(uid)
        let doc: DocumentSnapshot
        do {
            doc = try await ref.getDocument()
        } catch {
            throw MPError.network(error)
        }
        if doc.exists {
            do {
                let profile = try FirestoreCodable.decode(MPPlayerProfile.self, from: doc)
                await registerFCMToken(uid: uid)
                return profile
            } catch {
                throw MPError.network(error)
            }
        }
        // First launch: create the profile. The username is claimed later
        // via claimUsername; stats start at zero and stay function-written.
        let profile = MPPlayerProfile(id: uid, username: "")
        do {
            let data = try FirestoreCodable.encode(profile)
            try await ref.setData(data)
        } catch {
            throw MPError.network(error)
        }
        await registerFCMToken(uid: uid)
        return profile
    }

    func claimUsername(_ username: String) async throws -> MPPlayerProfile {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 16,
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { throw MPError.usernameInvalid }

        let uid = try self.uid
        let lower = trimmed.lowercased()
        let nameRef = db.collection("usernames").document(lower)
        let userRef = profileRef(uid)

        do {
            try await db.runTransaction { transaction, errorPointer in
                do {
                    // First writer wins: if the name doc exists, the name is taken.
                    let nameDoc = try transaction.getDocument(nameRef)
                    guard !nameDoc.exists else {
                        errorPointer?.pointee = NSError(domain: "SWISH.MPError", code: 1, userInfo: nil)
                        return nil
                    }
                    transaction.setData(["uid": uid], forDocument: nameRef)
                    transaction.updateData(["username": trimmed], forDocument: userRef)
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == "SWISH.MPError", nsError.code == 1 {
                throw MPError.usernameTaken
            }
            throw MPError.network(error)
        }
        return await currentProfile() ?? MPPlayerProfile(id: uid, username: trimmed)
    }

    func currentProfile() async -> MPPlayerProfile? {
        guard let uid = auth.currentUser?.uid else { return nil }
        guard let doc = try? await profileRef(uid).getDocument(), doc.exists else { return nil }
        return try? FirestoreCodable.decode(MPPlayerProfile.self, from: doc)
    }

    // MARK: - Matchmaking

    func findMatch(timeout: TimeInterval = MPConfig.matchmakingTimeout) async throws -> MPMatchSearchResult {
        let uid = try self.uid
        guard let profile = await currentProfile(), !profile.username.isEmpty else {
            throw MPError.notSignedIn
        }
        let ticketRef = db.collection("matchmaking").document(uid)
        do {
            try await ticketRef.setData([
                "uid": uid,
                "username": profile.username,
                "createdAt": FieldValue.serverTimestamp(),
                "status": "waiting",
            ])
        } catch {
            throw MPError.network(error)
        }

        // Poll for the matchmaking Cloud Function to pair us. Polling (not a
        // listener) keeps this simple and robust across app backgrounding.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            try Task.checkCancellation()
            guard let doc = try? await ticketRef.getDocument(), doc.exists,
                  let data = doc.data(),
                  let status = data["status"] as? String
            else { continue }
            if status == "matched", let matchId = data["matchId"] as? String {
                try? await ticketRef.delete()
                return .matched(try await getMatch(id: matchId))
            }
        }
        // Timeout: cancel the ticket. The caller offers a clearly-labeled
        // CPU game via BotBackfill — never a fake human.
        try? await ticketRef.delete()
        return .timedOut
    }

    func getMatch(id: String) async throws -> MPMatch {
        let ref = db.collection("matches").document(id)
        let doc: DocumentSnapshot
        do {
            doc = try await ref.getDocument()
        } catch {
            throw MPError.network(error)
        }
        guard doc.exists else { throw MPError.matchNotFound }
        var match: MPMatch
        do {
            match = try FirestoreCodable.decode(MPMatch.self, from: doc)
        } catch {
            throw MPError.network(error)
        }
        match.id = doc.documentID

        // Lazy forfeit evaluation (DESIGN.md §7): no scheduler needed.
        // If the turn deadline plus grace period has passed, ask the server
        // to finalize the forfeit, then re-read.
        if match.status == .active, let deadline = match.turnDeadline {
            let grace: TimeInterval = MPConfig.forfeitGraceHours * 3600
            if Date().timeIntervalSince(deadline) > grace {
                _ = try? await functions.httpsCallable("resolveForfeit").call(["matchId": id])
                if let fresh = try? await ref.getDocument(),
                   fresh.exists, var m = try? FirestoreCodable.decode(MPMatch.self, from: fresh) {
                    m.id = fresh.documentID
                    return m
                }
            }
        }
        return match
    }

    func myMatches() async throws -> [MPMatch] {
        let uid = try self.uid
        let snap: QuerySnapshot
        do {
            // arrayContains needs no composite index; sort client-side.
            snap = try await db.collection("matches")
                .whereField("playerIds", arrayContains: uid)
                .getDocuments()
        } catch {
            throw MPError.network(error)
        }
        var out: [MPMatch] = []
        for doc in snap.documents {
            if var m = try? FirestoreCodable.decode(MPMatch.self, from: doc) {
                m.id = doc.documentID
                out.append(m)
            }
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    func submitTurn(_ turn: MPTurn) async throws -> MPMatch {
        _ = try self.uid
        do {
            _ = try await functions.httpsCallable("submitTurn").call([
                "matchId": turn.matchId,
                "playerIndex": turn.playerIndex,
                "turnNumber": turn.turnNumber,
                "placements": turn.placements.map { ["cell": $0.cell, "letter": $0.letter] },
            ])
        } catch {
            throw mapFunctionError(error)
        }
        // Re-read the authoritative match from Firestore (avoids any
        // date-serialization issues in the callable response).
        return try await getMatch(id: turn.matchId)
    }

    func forfeit(matchId: String) async throws -> MPMatch {
        _ = try self.uid
        do {
            _ = try await functions.httpsCallable("forfeitMatch").call(["matchId": matchId])
        } catch {
            throw mapFunctionError(error)
        }
        return try await getMatch(id: matchId)
    }

    // MARK: - Friends

    func searchUser(username: String) async throws -> MPPlayerProfile? {
        _ = try self.uid
        let lower = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        let nameDoc: DocumentSnapshot
        do {
            nameDoc = try await db.collection("usernames").document(lower).getDocument()
        } catch {
            throw MPError.network(error)
        }
        guard let targetUid = nameDoc.data()?["uid"] as? String else { return nil }
        let profileDoc: DocumentSnapshot
        do {
            profileDoc = try await profileRef(targetUid).getDocument()
        } catch {
            throw MPError.network(error)
        }
        guard profileDoc.exists else { return nil }
        return try? FirestoreCodable.decode(MPPlayerProfile.self, from: profileDoc)
    }

    func challengeUser(uid targetUid: String) async throws -> MPChallenge {
        let uid = try self.uid
        guard targetUid != uid else { throw MPError.cannotChallengeSelf }
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("sendChallenge").call(["toUid": targetUid])
        } catch {
            throw mapFunctionError(error)
        }
        let data = result.data as? [String: Any]
        let challengeId = data?["challengeId"] as? String ?? UUID().uuidString
        let me = await currentProfile()
        return MPChallenge(
            id: challengeId,
            fromUid: uid,
            fromUsername: me?.username ?? "",
            toUid: targetUid,
            status: .pending,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(MPConfig.challengeExpiryHours * 3600)
        )
    }

    func myChallenges() async throws -> [MPChallenge] {
        let uid = try self.uid
        let snap: QuerySnapshot
        do {
            // No composite index needed: fetch and filter client-side.
            snap = try await profileRef(uid).collection("challenges").getDocuments()
        } catch {
            throw MPError.network(error)
        }
        var out: [MPChallenge] = []
        for doc in snap.documents {
            if var c = try? FirestoreCodable.decode(MPChallenge.self, from: doc), c.status == .pending {
                c.id = doc.documentID
                // Drop expired ones from the list (server expires them lazily).
                if c.expiresAt > Date() { out.append(c) }
            }
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    func respondToChallenge(id: String, accept: Bool) async throws -> MPMatch? {
        _ = try self.uid
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("respondToChallenge")
                .call(["challengeId": id, "accept": accept])
        } catch {
            throw mapFunctionError(error)
        }
        guard accept else { return nil }
        let data = result.data as? [String: Any]
        guard let matchId = data?["matchId"] as? String else { return nil }
        return try await getMatch(id: matchId)
    }

    // MARK: - Push registration

    /// Registers this device's FCM token on the profile so Cloud Functions
    /// can send "your turn" pushes. Best-effort: never fails sign-in.
    private func registerFCMToken(uid: String) async {
        guard let token = try? await Messaging.messaging().token(), !token.isEmpty else { return }
        try? await profileRef(uid).updateData([
            "fcmTokens": FieldValue.arrayUnion([token]),
            "lastSeenAt": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: - Error mapping

    private func mapFunctionError(_ error: Error) -> MPError {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: ns.code)
        else { return MPError.network(error) }
        let message = (ns.userInfo[FunctionsErrorDetailsKey] as? String) ?? ""
        switch code {
        case .unauthenticated:
            return .notSignedIn
        case .notFound:
            return message.contains("Challenge") ? .challengeNotFound : .matchNotFound
        case .permissionDenied:
            return .notYourTurn
        case .failedPrecondition:
            if message.contains("expired") { return .challengeExpired }
            if message.contains("Stale") { return .staleTurn }
            if message.contains("finished") { return .matchFinished }
            return .staleTurn
        case .invalidArgument:
            if message.contains("yourself") { return .cannotChallengeSelf }
            if message.contains("challenges") { return .tooManyPendingChallenges }
            return .network(error)
        case .resourceExhausted:
            if message.contains("challenge") { return .tooManyPendingChallenges }
            return .network(error)
        default:
            return .network(error)
        }
    }
}

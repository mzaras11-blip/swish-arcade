import Foundation

// MARK: - S.W.I.S.H async multiplayer: client models
//
// Codable value types shared between the app and the MultiplayerBackend
// protocol. The Firebase implementation (later) maps these to Firestore
// documents (Date <-> Timestamp). No Firebase imports here on purpose:
// the backend is swappable.

// MARK: - Player profile

/// Public profile. Win/loss records are written ONLY by Cloud Functions
/// when a match finishes — the client can never edit its own stats.
struct MPPlayerProfile: Codable, Identifiable, Hashable {
    /// Firebase Auth uid. Also the Identifiable id.
    var id: String = ""
    /// Unique, case-insensitive. 3-16 chars, [A-Za-z0-9_].
    var username: String
    var wins: Int = 0
    var losses: Int = 0
    var draws: Int = 0
    var createdAt: Date = Date()
}

// MARK: - Match

enum MPMatchStatus: String, Codable {
    /// Challenge accepted / players matched, game not started yet.
    case waiting
    /// Turns are being played.
    case active
    /// Winner decided (completed or forfeit).
    case finished
}

enum MPMatchEndReason: String, Codable {
    case completed
    case forfeit
}

/// One placement within a turn: a rack letter locked into a board cell.
/// `cell` is an index into `Puzzle.cells`; `letter` is one uppercase letter.
struct MPPlacement: Codable, Hashable {
    var cell: Int
    var letter: String
}

/// A submitted turn. The client sends placements only — the server
/// validates them and computes scoreDelta/wordsCompleted. Never trust
/// a client-sent score.
struct MPTurn: Codable, Identifiable {
    /// "<matchId>:<turnNumber>" — makes resubmits idempotent.
    var id: String { "\(matchId):\(turnNumber)" }
    var matchId: String
    var playerIndex: Int
    var turnNumber: Int
    var placements: [MPPlacement]
    var submittedAt: Date = Date()

    // Filled in by the server after validation:
    var scoreDelta: Int?
    var wordsCompleted: [Int]?
}

/// A full async match. Created ONLY by Cloud Functions; clients read it.
struct MPMatch: Codable, Identifiable, Hashable {
    var id: String = ""
    /// Auth uids, index 0/1 = player index used everywhere else.
    var playerIds: [String]
    /// Denormalized display names, aligned with playerIds.
    var usernames: [String]
    /// The identical board for both players, dealt by the server.
    /// Decodes with the existing Puzzle struct and feeds straight
    /// into GameViewModel.
    var puzzle: Puzzle
    /// Current 5-tile racks, aligned with playerIds. Dealt by the server.
    var currentRacks: [[String]]
    var turnNumber: Int
    /// Index into playerIds whose turn it is.
    var currentPlayer: Int
    /// When the current turn expires (nil while waiting).
    var turnDeadline: Date?
    var scores: [Int]
    /// Word indices already completed (mirrors GameViewModel.completedWords).
    var completedWords: [Int]
    /// Per cell: which player placed it (nil = empty). Mirrors filledBy.
    var filledBy: [Int?]
    var status: MPMatchStatus
    var winnerIndex: Int?
    var endReason: MPMatchEndReason?
    var createdAt: Date
    var updatedAt: Date

    /// Convenience: the opponent's uid/username from one player's view.
    func opponent(of uid: String) -> (uid: String, username: String)? {
        guard let me = playerIds.firstIndex(of: uid), playerIds.count == 2 else { return nil }
        let them = 1 - me
        return (playerIds[them], usernames[them])
    }

    /// Convenience: my player index, if I'm in this match.
    func playerIndex(of uid: String) -> Int? {
        playerIds.firstIndex(of: uid)
    }

    // MARK: - Hashable (identity by id; used for navigation)
    static func == (lhs: MPMatch, rhs: MPMatch) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Friend challenges

enum MPChallengeStatus: String, Codable {
    case pending
    case accepted
    case declined
    case expired
}

/// A direct challenge to a friend by username. Lives under the
/// recipient's profile; created by the challenger, answered by the
/// recipient, match built by a Cloud Function on accept.
struct MPChallenge: Codable, Identifiable {
    var id: String = ""
    var fromUid: String
    var fromUsername: String
    var toUid: String
    var status: MPChallengeStatus
    var createdAt: Date
    var expiresAt: Date
}

// MARK: - Matchmaking result

/// Outcome of findMatch(). On .timedOut the UI offers a clearly-labeled
/// CPU game — never a fake human.
enum MPMatchSearchResult {
    case matched(MPMatch)
    case timedOut
}

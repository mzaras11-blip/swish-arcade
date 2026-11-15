import Foundation

// MARK: - S.W.I.S.H async multiplayer: backend contract
//
// The entire online layer talks through this protocol. The Firebase
// implementation (Firestore + Auth + Functions + FCM) comes later and
// plugs in here; the UI and game code never touch Firebase directly.

// MARK: - Errors

enum MPError: Error, LocalizedError {
    case notSignedIn
    case usernameTaken
    case usernameInvalid
    case noOpponentFound
    case matchNotFound
    case notYourTurn
    case staleTurn
    case matchFinished
    case challengeNotFound
    case challengeExpired
    case cannotChallengeSelf
    case tooManyPendingChallenges
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You're not signed in."
        case .usernameTaken: return "That username is taken — try another."
        case .usernameInvalid: return "Usernames are 3–16 letters, numbers, or underscores."
        case .noOpponentFound: return "No players waiting right now."
        case .matchNotFound: return "That match no longer exists."
        case .notYourTurn: return "It's not your turn."
        case .staleTurn: return "That turn was already submitted."
        case .matchFinished: return "This match is over."
        case .challengeNotFound: return "That challenge is gone."
        case .challengeExpired: return "That challenge expired."
        case .cannotChallengeSelf: return "You can't challenge yourself."
        case .tooManyPendingChallenges: return "You have too many open challenges."
        case .network(let e): return e.localizedDescription
        }
    }
}

// MARK: - Tunables (mirrors DESIGN.md §11)

enum MPConfig {
    /// How long findMatch waits for a human before giving up.
    static let matchmakingTimeout: TimeInterval = 30
    /// Turn window, Kryss-style async.
    static let turnDeadlineHours: Double = 24
    /// Extra time after a missed deadline before the forfeit is applied.
    static let forfeitGraceHours: Double = 24
    static let maxPendingChallenges: Int = 5
    static let challengeExpiryHours: Double = 24
}

// MARK: - Backend protocol

/// All online multiplayer goes through here. Implementations must be
/// server-authoritative: the backend deals puzzles and racks, validates
/// turns, and computes every point. The client only *requests* actions.
protocol MultiplayerBackend {

    // MARK: Identity

    /// Signs in (Firebase: anonymous auth, upgradeable to Apple Sign-In
    /// later). Returns the player's profile, creating it if needed.
    func signIn() async throws -> MPPlayerProfile

    /// Claims a unique username (case-insensitive). Throws
    /// .usernameTaken / .usernameInvalid.
    func claimUsername(_ username: String) async throws -> MPPlayerProfile

    /// The currently signed-in profile, if any.
    func currentProfile() async -> MPPlayerProfile?

    // MARK: Matchmaking

    /// Writes a matchmaking ticket and waits up to `timeout` for a human
    /// opponent. Returns `.matched` or `.timedOut` — on timeout the caller
    /// offers a clearly-labeled CPU game via BotBackfill (never a fake
    /// human). Cancels the ticket on timeout.
    func findMatch(timeout: TimeInterval) async throws -> MPMatchSearchResult

    /// Fetches a match. Implementations should lazily evaluate turn
    /// deadlines/forfeits here (see DESIGN.md §7) so no scheduler is needed.
    func getMatch(id: String) async throws -> MPMatch

    /// All matches I'm in, newest first (for the match list screen).
    func myMatches() async throws -> [MPMatch]

    /// Submits my placements for the current turn. The backend validates
    /// legality and recomputes scoring; the returned match is authoritative.
    func submitTurn(_ turn: MPTurn) async throws -> MPMatch

    /// Give up this match voluntarily. Opponent wins by forfeit.
    func forfeit(matchId: String) async throws -> MPMatch

    // MARK: Friends

    /// Exact username lookup (case-insensitive). Returns nil when nobody
    /// has that name.
    func searchUser(username: String) async throws -> MPPlayerProfile?

    /// Sends a challenge to another player. Throws .cannotChallengeSelf /
    /// .tooManyPendingChallenges.
    func challengeUser(uid: String) async throws -> MPChallenge

    /// Challenges waiting for me to answer.
    func myChallenges() async throws -> [MPChallenge]

    /// Accept or decline. Accept returns the new match (built server-side);
    /// decline returns nil.
    func respondToChallenge(id: String, accept: Bool) async throws -> MPMatch?
}

// MARK: - Honest bot backfill
//
// HARD RULE: bots are never presented as human players. When matchmaking
// times out, the app may offer a game against the CPU — always labeled
// "CPU", never with a human-sounding name or avatar. This helper is the
// single choke point for that flow so the rule can't be bypassed by
// accident.

/// Request to start a local CPU game after matchmaking found no human.
/// The UI builds it with the existing offline engine, e.g.
/// `GameViewModel(puzzle: freshPuzzle, mode: .solo(request.difficulty))`.
struct CPUBotGameRequest {
    /// Reuses the existing AI difficulty (easy/normal/hard in Models.swift).
    /// The local AI implementation itself is NOT duplicated here.
    var difficulty: Difficulty

    /// The ONLY label a bot opponent may ever carry.
    var opponentLabel: String { "CPU" }
}

enum BotBackfill {
    /// Call this when `findMatch` returns `.timedOut`. Presents the
    /// difficulty picker; the resulting game is offline solo-vs-CPU with
    /// the opponent visibly labeled CPU.
    static func requestCPUGame(difficulty: Difficulty) -> CPUBotGameRequest {
        CPUBotGameRequest(difficulty: difficulty)
    }
}

import Foundation

// MARK: - Lifetime stats (solo vs CPU)

/// Persists per-game results for the Stats screen.
enum StatsStore {
    private static let winsKey = "swish_stat_wins"
    private static let lossesKey = "swish_stat_losses"
    private static let drawsKey = "swish_stat_draws"
    private static let last10Key = "swish_stat_last10"   // 1 = win, 0 = draw, -1 = loss
    private static let lettersKey = "swish_stat_letters" // player letters placed (solo)
    private static let turnsKey = "swish_stat_turns"     // player turns taken (solo)
    private static let localKey = "swish_stat_local_games"

    /// - Parameters:
    ///   - winner: 0 = player 1 won, 1 = player 2 / CPU won, nil = draw
    ///   - solo: true when vs CPU
    static func recordGame(winner: Int?, solo: Bool, lettersPlaced: Int, turnsTaken: Int) {
        let d = UserDefaults.standard
        PlayReminder.shared.recordPlay()
        if solo {
            if winner == 0 { d.set(d.integer(forKey: winsKey) + 1, forKey: winsKey) }
            else if winner == 1 { d.set(d.integer(forKey: lossesKey) + 1, forKey: lossesKey) }
            else { d.set(d.integer(forKey: drawsKey) + 1, forKey: drawsKey) }
            var last = d.array(forKey: last10Key) as? [Int] ?? []
            last.append(winner == 0 ? 1 : (winner == nil ? 0 : -1))
            d.set(Array(last.suffix(10)), forKey: last10Key)
            d.set(d.integer(forKey: lettersKey) + lettersPlaced, forKey: lettersKey)
            d.set(d.integer(forKey: turnsKey) + turnsTaken, forKey: turnsKey)
        } else {
            d.set(d.integer(forKey: localKey) + 1, forKey: localKey)
        }
    }

    struct Summary {
        let wins: Int
        let losses: Int
        let draws: Int
        let last10: [Int]
        let avgLettersPerTurn: Double
        let localGames: Int
        var winRate: Double {
            let played = wins + losses + draws
            return played == 0 ? 0 : Double(wins) / Double(played)
        }
    }

    static func summary() -> Summary {
        let d = UserDefaults.standard
        let turns = d.integer(forKey: turnsKey)
        let letters = d.integer(forKey: lettersKey)
        return Summary(
            wins: d.integer(forKey: winsKey),
            losses: d.integer(forKey: lossesKey),
            draws: d.integer(forKey: drawsKey),
            last10: d.array(forKey: last10Key) as? [Int] ?? [],
            avgLettersPerTurn: turns == 0 ? 0 : Double(letters) / Double(turns),
            localGames: d.integer(forKey: localKey)
        )
    }
}

// MARK: - Daily missions

/// A rotating set of 3 lightweight daily goals, tracked on-device.
/// (Kryss runs server-driven missions; this is the honest local equivalent.)
struct Mission: Identifiable {
    let id: String
    let title: String
    let target: Int
    let progress: Int
    var isComplete: Bool { progress >= target }
}

enum MissionStore {
    struct Template {
        let id: String
        let title: String
        let target: Int
    }

    private static let templates: [Template] = [
        Template(id: "score", title: "Score 120 points in one game", target: 120),
        Template(id: "allfive", title: "Place all 5 tiles in one turn", target: 1),
        Template(id: "words", title: "Complete 4 words in a day", target: 4),
        Template(id: "win", title: "Win a solo game", target: 1),
        Template(id: "letters", title: "Place 30 letters in a day", target: 30),
        Template(id: "blue", title: "Hit a blue bonus square", target: 1),
    ]

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "swish_missions_" + f.string(from: Date())
    }

    /// Deterministic 3-mission rotation seeded by the date.
    static func todayMissions() -> [Mission] {
        let key = dayKey()
        var seed = UInt64(bitPattern: Int64(key.hashValue))
        if seed == 0 { seed = 0x9E3779B97F4A7C15 }
        // xorshift64 for a stable daily pick
        func next(_ n: Int) -> Int {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Int(seed % UInt64(max(n, 1)))
        }
        var pool = templates
        var picked: [Template] = []
        for _ in 0..<min(3, pool.count) {
            picked.append(pool.remove(at: next(pool.count)))
        }
        let d = UserDefaults.standard
        let saved = d.dictionary(forKey: key) as? [String: Int] ?? [:]
        return picked.map { t in
            Mission(id: t.id, title: t.title, target: t.target,
                    progress: min(saved[t.id] ?? 0, t.target))
        }
    }

    private static func bump(_ id: String, to value: Int? = nil, by delta: Int = 0) {
        let key = dayKey()
        let d = UserDefaults.standard
        var saved = d.dictionary(forKey: key) as? [String: Int] ?? [:]
        let cur = saved[id] ?? 0
        saved[id] = value.map { max(cur, $0) } ?? (cur + delta)
        d.set(saved, forKey: key)
    }

    // Event hooks called from GameViewModel.
    static func letterPlaced() { bump("letters", by: 1) }
    static func wordCompleted() { bump("words", by: 1) }
    static func allFiveTurn() { bump("allfive", by: 1) }
    static func blueSquareHit() { bump("blue", by: 1) }
    static func gameScore(_ s: Int) { bump("score", to: s) }
    static func soloWin() { bump("win", by: 1) }
}

// MARK: - Recent games (rematch list)

/// Last finished games, so any of them can be rematched from Stats.
struct RecentGame: Codable, Identifiable {
    let id: UUID
    let date: Date
    let modeLabel: String
    let difficultyRaw: String?
    let names: [String]
    let scores: [Int]
    let winner: Int?
    /// False when the game was played in text-only (advanced) clue mode.
    /// Defaults to true so entries saved before this existed still decode.
    var pictureClues: Bool = true

    var mode: GameMode {
        // modeLabel is the source of truth for modes without a difficulty.
        if modeLabel == "Practice" { return .practice }
        if modeLabel == "Elements (Advanced)" { return .elements }
        if modeLabel.hasPrefix("Blitz (") {
            if let raw = difficultyRaw, let d = Difficulty(rawValue: raw) {
                return .blitz(d)
            }
            return .blitz(.normal)
        }
        if let raw = difficultyRaw, let d = Difficulty(rawValue: raw) {
            return .solo(d)
        }
        return .passAndPlay
    }

    var resultText: String {
        if let w = winner { return "\(names[w]) won" }
        return "Draw"
    }
}

enum RecentGamesStore {
    private static let key = "swish_recent_games"
    private static let maxCount = 10

    static func record(modeLabel: String, difficultyRaw: String?,
                       names: [String], scores: [Int], winner: Int?,
                       pictureClues: Bool = true) {
        var games = list()
        games.insert(RecentGame(id: UUID(), date: Date(), modeLabel: modeLabel,
                                difficultyRaw: difficultyRaw, names: names,
                                scores: scores, winner: winner,
                                pictureClues: pictureClues), at: 0)
        games = Array(games.prefix(maxCount))
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func list() -> [RecentGame] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let games = try? JSONDecoder().decode([RecentGame].self, from: data)
        else { return [] }
        return games
    }
}

// MARK: - Daily streak

/// Consecutive days with at least one finished daily-puzzle game.
enum StreakStore {
    private static let countKey = "swish_streak_count"
    private static let lastKey = "swish_streak_last"
    /// All days a daily-puzzle game was finished ("yyyy-MM-dd"), oldest first.
    private static let daysKey = "swish_streak_days"

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Call when a daily-puzzle game finishes. Returns the current streak.
    @discardableResult
    static func recordDailyGame() -> Int {
        let d = UserDefaults.standard
        let today = dayString(Date())
        let yesterday = dayString(Date().addingTimeInterval(-86400))
        let last = d.string(forKey: lastKey)
        let count: Int
        if last == today {
            count = d.integer(forKey: countKey)
        } else if last == yesterday {
            count = d.integer(forKey: countKey) + 1
        } else {
            count = 1
        }
        d.set(count, forKey: countKey)
        d.set(today, forKey: lastKey)
        // Completion-day log for the streak calendar (existing logic untouched).
        var days = d.stringArray(forKey: daysKey) ?? []
        if days.last != today {
            days.append(today)
            if days.count > 400 { days.removeFirst(days.count - 400) }
            d.set(days, forKey: daysKey)
        }
        return count
    }

    /// Every recorded completion day ("yyyy-MM-dd"), oldest first.
    static func completionDays() -> [String] {
        UserDefaults.standard.stringArray(forKey: daysKey) ?? []
    }

    static func current() -> (streak: Int, playedToday: Bool) {
        let d = UserDefaults.standard
        let playedToday = d.string(forKey: lastKey) == dayString(Date())
        // A streak lapses if yesterday wasn't played either.
        let yesterday = dayString(Date().addingTimeInterval(-86400))
        let last = d.string(forKey: lastKey)
        let streak = (last == dayString(Date()) || last == yesterday)
            ? d.integer(forKey: countKey) : 0
        return (streak, playedToday)
    }
}

// MARK: - Daily puzzle cache

/// One shared puzzle per calendar day, cached on-device.
enum DailyPuzzleStore {
    private static func fileURL() -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let name = "swish-daily-" + f.string(from: Date()) + ".json"
        return FileManager.default.urls(for: .cachesDirectory,
                                        in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    static func load() -> Puzzle? {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(Puzzle.self, from: data)
        else { return nil }
        return p
    }

    static func save(_ p: Puzzle) {
        guard let url = fileURL(),
              let data = try? JSONEncoder().encode(p) else { return }
        try? data.write(to: url)
    }
}

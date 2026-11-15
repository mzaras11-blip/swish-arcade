import Foundation
import SwiftUI
import Combine
import UIKit

struct PopupMessage: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

final class GameViewModel: ObservableObject {
    static let turnSeconds = 60
    static let rackSize = 5

    let puzzle: Puzzle
    let mode: GameMode
    let playerNames: [String]

    // Board state
    @Published var filled: [String?]
    @Published var filledBy: [Int?]
    @Published var completedWords: Set<Int> = []

    // Turn state
    @Published var rack: [Tile] = []
    @Published var selectedTileID: UUID?
    @Published var scores = [0, 0]
    @Published var currentPlayer = 0
    @Published var secondsLeft = turnSeconds
    @Published var turnPlacements = 0
    @Published var turnPoints = 0
    @Published var blueHit = false
    @Published var turnNumber = 1

    // Kryss-style turn tools
    @Published var turnCells: Set<Int> = []

    /// Time-boost power-up: +30s on the turn clock, 2 per game.
    @Published var timeBoostsLeft = 2
    @Published var discardsLeft = maxDiscardsPerGame
    static let maxDiscardsPerGame = 2
    /// Swap-2 picking flow: tap the button, pick 2 rack tiles, confirm.
    @Published var swapPicking = false
    @Published var swapPicked: Set<UUID> = []
    private var turnMoves: [(cell: Int, tileID: UUID)] = []
    /// Cells hit on a blue bonus square this turn (drives the x2 badge).
    @Published private(set) var turnBlueCells: Set<Int> = []

    // Stats bookkeeping
    private var lettersPlacedCount = [0, 0]
    private var turnsTakenCount = [0, 0]
    private var consecutiveEmptyTurns = 0
    private var wordsCompletedCount = [0, 0]
    private var cleanSweeps = [0, 0]

    /// True when this game is the daily puzzle (feeds the streak).
    let isDaily: Bool

    /// When false, clue cells always show text — the advanced, no-picture mode.
    let pictureCluesEnabled: Bool

    // UI state
    @Published var gameOver = false
    @Published var winner: Int? = nil
    /// Set when a player forfeits: the other side wins outright.
    private var forfeitedBy: Int? = nil
    @Published var showForfeitConfirm = false
    @Published var toast: String? = nil
    @Published var shakeTileID: UUID? = nil
    @Published var aiBusy = false
    @Published var popup: PopupMessage? = nil
    @Published var dropTarget: Int? = nil

    // Ads
    let adManager = AdManager.shared
    @Published var hintsUsed = 0
    static let maxHintsPerGame = 3
    var hintsLeft: Int { Self.maxHintsPerGame - hintsUsed }

    // Precomputed lookups
    private var wordCells: [[Int]] = []
    private var cellWords: [[Int]] = []
    private var aiKnown: Set<Int> = []

    private var timer: Timer?
    private var toastTask: DispatchWorkItem?

    // Blitz mode: 5-minute game clock.
    @Published var blitzSecondsLeft = blitzSeconds
    static let blitzSeconds = 300
    private var blitzTimer: Timer?

    deinit {
        timer?.invalidate()
        blitzTimer?.invalidate()
    }

    var isAITurn: Bool {
        if case .solo = mode { return currentPlayer == 1 }
        if case .elements = mode { return currentPlayer == 1 }
        if case .blitz = mode { return currentPlayer == 1 }
        return false
    }
    var isHumanTurn: Bool { !isAITurn && !gameOver }

    /// Quick 5-minute battle vs CPU.
    var isBlitz: Bool {
        if case .blitz = mode { return true }
        return false
    }

    /// Relaxed solo mode: no timer, no CPU opponent.
    var isPractice: Bool {
        if case .practice = mode { return true }
        return false
    }

    var difficulty: Difficulty {
        if case .solo(let d) = mode { return d }
        if case .elements = mode { return .hard } // advanced mode: hard CPU
        if case .blitz(let d) = mode { return d }
        return .normal
    }

    /// "4:32"-style countdown string for the blitz game clock.
    var blitzClock: String {
        String(format: "%d:%02d", blitzSecondsLeft / 60, blitzSecondsLeft % 60)
    }

    /// The losing player once the game is over (nil for a tie or mid-game).
    var loser: Int? {
        guard gameOver else { return nil }
        if scores[0] < scores[1] { return 0 }
        if scores[1] < scores[0] { return 1 }
        return nil
    }

    // MARK: - Results-screen stats

    var wordsCompleted: [Int] { wordsCompletedCount }

    var lettersPlaced: [Int] { lettersPlacedCount }

    var avgLettersPerTurn: [Double] {
        [0, 1].map { p in
            let t = turnsTakenCount[p]
            return t == 0 ? 0 : Double(lettersPlacedCount[p]) / Double(t)
        }
    }

    var cleanSweepRate: [Double] {
        [0, 1].map { p in
            let t = turnsTakenCount[p]
            return t == 0 ? 0 : Double(cleanSweeps[p]) / Double(t)
        }
    }

    // MARK: - Init

    init(puzzle: Puzzle, mode: GameMode, headStartPlayer: Int? = nil,
         isDaily: Bool = false, pictureClues: Bool = true) {
        self.puzzle = puzzle
        self.mode = mode
        self.isDaily = isDaily
        self.pictureCluesEnabled = pictureClues
        switch mode {
        case .solo: self.playerNames = ["You", "CPU"]
        case .elements: self.playerNames = ["You", "CPU"]
        case .practice: self.playerNames = ["You"]
        case .blitz: self.playerNames = ["You", "CPU"]
        case .passAndPlay: self.playerNames = ["Player 1", "Player 2"]
        }
        let n = puzzle.cells.count
        self.filled = Array(repeating: nil, count: n)
        self.filledBy = Array(repeating: nil, count: n)

        // Build word -> cells and cell -> words lookups
        var wc: [[Int]] = Array(repeating: [], count: puzzle.words.count)
        var cw: [[Int]] = Array(repeating: [], count: n)
        for (wi, w) in puzzle.words.enumerated() {
            for i in 0..<w.a.count {
                let idx = (w.d == "across")
                    ? w.r * puzzle.cols + (w.c + i)
                    : (w.r + i) * puzzle.cols + w.c
                wc[wi].append(idx)
                cw[idx].append(wi)
            }
        }
        self.wordCells = wc
        self.cellWords = cw

        // AI "knows" a random subset of the words
        let all = Array(0..<puzzle.words.count).shuffled()
        let k = Int((Double(puzzle.words.count) * difficulty.knownFraction).rounded(.up))
        self.aiKnown = Set(all.prefix(max(1, k)))

        dealRack()
        if !isPractice { startTimer() }
        if isBlitz { startBlitzTimer() }

        if let p = headStartPlayer, p == 0 || p == 1 {
            scores[p] = 5
            showToast("\(playerNames[p]) starts +5!")
        }
    }

    // MARK: - Helpers

    func isLetterCell(_ i: Int) -> Bool { puzzle.cells[i].k == "l" }
    func isClueCell(_ i: Int) -> Bool { puzzle.cells[i].k == "c" }
    func solution(_ i: Int) -> String { puzzle.cells[i].s ?? "" }
    func isBonus(_ i: Int) -> Bool { puzzle.cells[i].b == true }

    func clueText(_ i: Int) -> String {
        let cell = puzzle.cells[i]
        var parts: [String] = []
        if let a = cell.ca { parts.append("\u{2192} " + a) }
        if let d = cell.cd { parts.append("\u{2193} " + d) }
        return parts.joined(separator: "\n")
    }

    // MARK: - Picture clues

    /// Words whose clue lives in the given clue cell
    /// (across word starts one cell right, down word one cell below).
    func cluedWords(_ i: Int) -> [PuzzleWord] {
        let r = i / puzzle.cols, c = i % puzzle.cols
        return puzzle.words.filter { w in
            (w.d == "across" && w.r == r && w.c == c + 1)
            || (w.d == "down" && w.r == r + 1 && w.c == c)
        }
    }

    /// SF Symbol name for this clue cell, when its word has a picture.
    func pictureSymbolForClue(_ i: Int) -> String? {
        for w in cluedWords(i) {
            if let s = PictureClues.symbol(forWord: w.a) { return s }
        }
        return nil
    }

    private func remainingInWord(_ wi: Int) -> Int {
        wordCells[wi].filter { filled[$0] == nil }.count
    }

    private func isBoardFull() -> Bool {
        for i in 0..<puzzle.cells.count {
            if isLetterCell(i) && filled[i] == nil { return false }
        }
        return true
    }

    // MARK: - Turn flow

    private func dealRack() {
        rack = drawTiles(Self.rackSize)
        selectedTileID = nil
    }

    private func startTimer() {
        stopTimer()
        secondsLeft = Self.turnSeconds
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.secondsLeft -= 1
            if self.secondsLeft <= 0 {
                self.endTurn()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startBlitzTimer() {
        stopBlitzTimer()
        blitzSecondsLeft = Self.blitzSeconds
        blitzTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.blitzSecondsLeft -= 1
            if self.blitzSecondsLeft <= 0 {
                self.endGame()
            }
        }
    }

    private func stopBlitzTimer() {
        blitzTimer?.invalidate()
        blitzTimer = nil
    }

    func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        let task = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: task)
    }

    /// Attempt to place a rack tile onto a board cell.
    func attemptPlace(tileID: UUID, cell: Int) {
        guard !gameOver else { return }
        guard isLetterCell(cell), filled[cell] == nil else { return }
        guard let ti = rack.firstIndex(where: { $0.id == tileID }), !rack[ti].used else { return }

        let letter = rack[ti].letter
        if letter == solution(cell) {
            rack[ti].used = true
            if selectedTileID == tileID { selectedTileID = nil }
            lockLetter(cell: cell, countsTowardBonus: true)
            turnMoves.append((cell: cell, tileID: tileID))
            turnCells.insert(cell)
            if isBonus(cell) { turnBlueCells.insert(cell) }
            haptic(.medium)

            if isBoardFull() {
                endGame()
            }
        } else {
            // Wrong square: tile bounces back
            haptic(.light)
            shakeTileID = tileID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.shakeTileID == tileID { self?.shakeTileID = nil }
            }
        }
    }

    /// Light tactile feedback for tile placement.
    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Locks a correct letter into a cell and awards points.
    /// - Parameter countsTowardBonus: rack placements count toward the "all 5" bonus;
    ///   ad-earned hint letters do not.
    private func lockLetter(cell: Int, countsTowardBonus: Bool) {
        filled[cell] = solution(cell)
        filledBy[cell] = currentPlayer
        scores[currentPlayer] += 1
        turnPoints += 1
        if countsTowardBonus {
            turnPlacements += 1
            lettersPlacedCount[currentPlayer] += 1
            if !isAITurn { MissionStore.letterPlaced() }
        }
        if isBonus(cell) {
            blueHit = true
            if !isAITurn { MissionStore.blueSquareHit() }
        }

        // Word completions (a placement can finish two words at a crossing)
        for wi in cellWords[cell] {
            if !completedWords.contains(wi)
                && wordCells[wi].allSatisfy({ filled[$0] != nil }) {
                completedWords.insert(wi)
                let bonus = puzzle.words[wi].a.count
                scores[currentPlayer] += bonus
                turnPoints += bonus
                wordsCompletedCount[currentPlayer] += 1
                if !isAITurn { MissionStore.wordCompleted() }
                showToast("Word complete! +\(bonus)")
            }
        }
    }

    /// Takes back the most recently placed tile this turn (Kryss-style undo).
    func undoLast() {
        guard isHumanTurn, !gameOver, let last = turnMoves.popLast() else { return }
        let cell = last.cell
        if let ti = rack.firstIndex(where: { $0.id == last.tileID }) {
            rack[ti].used = false
        }
        if selectedTileID == last.tileID { selectedTileID = nil }
        filled[cell] = nil
        filledBy[cell] = nil
        turnCells.remove(cell)
        turnBlueCells.remove(cell)
        blueHit = !turnBlueCells.isEmpty
        scores[currentPlayer] = max(0, scores[currentPlayer] - 1)
        turnPoints = max(0, turnPoints - 1)
        turnPlacements = max(0, turnPlacements - 1)
        lettersPlacedCount[currentPlayer] = max(0, lettersPlacedCount[currentPlayer] - 1)
        // Revoke any word bonus this placement had completed.
        for wi in cellWords[cell] where completedWords.contains(wi) {
            completedWords.remove(wi)
            let bonus = puzzle.words[wi].a.count
            scores[currentPlayer] = max(0, scores[currentPlayer] - bonus)
            turnPoints = max(0, turnPoints - bonus)
            showToast("Word un-completed \u{2212}\(bonus)")
        }
    }

    /// Swap 2: tap the button to enter picking mode, tap any 2 rack tiles,
    /// then confirm to exchange them for fresh ones. Twice per game.
    func startSwapPicking() {
        guard isHumanTurn, !gameOver, discardsLeft > 0 else { return }
        swapPicking = true
        swapPicked = []
        selectedTileID = nil
        showToast("Tap 2 tiles to swap")
    }

    func toggleSwapPick(_ id: UUID) {
        guard swapPicking, isHumanTurn, !gameOver else { return }
        guard let ti = rack.firstIndex(where: { $0.id == id }), !rack[ti].used else { return }
        if swapPicked.contains(id) {
            swapPicked.remove(id)
        } else if swapPicked.count < 2 {
            swapPicked.insert(id)
            haptic(.light)
        }
    }

    func cancelSwapPicking() {
        swapPicking = false
        swapPicked = []
    }

    func confirmSwap() {
        guard isHumanTurn, !gameOver, discardsLeft > 0, swapPicked.count == 2 else { return }
        for id in swapPicked {
            if let ti = rack.firstIndex(where: { $0.id == id }) {
                rack[ti] = Tile(letter: letterBag.randomElement() ?? "E")
            }
        }
        discardsLeft -= 1
        swapPicking = false
        swapPicked = []
        selectedTileID = nil
        showToast("Tiles swapped!")
    }

    /// Forfeit: ends the game immediately as a loss for the forfeiting player.
    func forfeit() {
        guard !gameOver else { return }
        forfeitedBy = currentPlayer
        showForfeitConfirm = false
        endGame()
    }

    func endTurn() {
        guard !gameOver else { return }
        stopTimer()

        if turnPlacements == Self.rackSize {
            scores[currentPlayer] += 5
            turnPoints += 5
            cleanSweeps[currentPlayer] += 1
            showToast("All 5 letters placed! +5")
            if !isAITurn { MissionStore.allFiveTurn() }
        }
        if blueHit && turnPoints > 0 {
            scores[currentPlayer] += turnPoints
            showToast("Blue square \u{2014} turn score doubled!")
        }

        // Kryss-style early end: only a few letters left and two
        // consecutive turns with no placements -> wrap it up.
        let empties = (0..<filled.count).filter { isLetterCell($0) && filled[$0] == nil }.count
        if turnPlacements == 0 { consecutiveEmptyTurns += 1 }
        else { consecutiveEmptyTurns = 0 }
        let stalled = empties < 10 && consecutiveEmptyTurns >= 2

        // Web parity: warn when few squares remain or a stall could end the game.
        // (Bonus toasts above take precedence; these only fire otherwise.)
        if turnPlacements != Self.rackSize && !(blueHit && turnPoints > 0) {
            if consecutiveEmptyTurns == 1 && empties < 10 {
                showToast("No placements \u{2014} another empty turn ends the game")
            } else if empties <= 10 && empties > 0 {
                showToast("Only \(empties) squares left!")
            }
        }

        turnsTakenCount[currentPlayer] += 1
        turnNumber += 1
        turnPlacements = 0
        turnPoints = 0
        blueHit = false
        turnMoves = []
        turnCells = []
        turnBlueCells = []
        selectedTileID = nil

        if stalled {
            endGame()
            return
        }

        if isPractice {
            // Practice: no opponent and no timer — just deal a fresh rack.
            dealRack()
            return
        }

        currentPlayer = 1 - currentPlayer
        dealRack()
        startTimer()

        if isAITurn {
            runAI()
        }
    }

    private func endGame() {
        guard !gameOver else { return } // idempotent: blitz clock and turn timer can race
        stopTimer()
        stopBlitzTimer()
        gameOver = true
        if let f = forfeitedBy {
            // Forfeit: the other side wins outright (practice has no opponent).
            winner = isPractice ? nil : 1 - f
        }
        else if scores[0] > scores[1] { winner = 0 }
        else if scores[1] > scores[0] { winner = 1 }
        else { winner = nil }
        // Persist stats + daily missions
        let solo: Bool
        switch mode {
        case .solo, .elements, .blitz: solo = true
        case .practice, .passAndPlay: solo = false
        }
        StatsStore.recordGame(winner: winner, solo: solo,
                              lettersPlaced: lettersPlacedCount[0],
                              turnsTaken: max(turnsTakenCount[0], 1))
        if solo {
            MissionStore.gameScore(scores[0])
            if winner == 0 { MissionStore.soloWin() }
        }
        if isDaily { StreakStore.recordDailyGame() }
        let modeLabel: String
        let difficultyRaw: String?
        switch mode {
        case .solo(let d):
            let style = pictureCluesEnabled ? "" : ", text only"
            modeLabel = isDaily ? "Daily Puzzle" : "Solo (\(d.title)\(style))"
            difficultyRaw = d.rawValue
        case .elements:
            modeLabel = "Elements (Advanced)"
            difficultyRaw = Difficulty.hard.rawValue
        case .practice:
            modeLabel = "Practice"
            difficultyRaw = nil
        case .blitz(let d):
            modeLabel = "Blitz (\(d.title))"
            difficultyRaw = d.rawValue
        case .passAndPlay:
            modeLabel = "Pass & Play"
            difficultyRaw = nil
        }
        RecentGamesStore.record(modeLabel: modeLabel, difficultyRaw: difficultyRaw,
                                names: playerNames, scores: scores, winner: winner,
                                pictureClues: pictureCluesEnabled)
        // Legacy counters
        let key: String
        if solo {
            key = (winner == 0) ? "swish_solo_wins" : "swish_solo_losses"
        } else {
            key = "swish_local_games"
        }
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }

    // MARK: - Rewarded hints (ad logic)

    /// Watches a rewarded ad, then reveals one correct letter as a hint.
    /// Fully player-initiated and transparent: nothing is rigged behind the scenes.
    /// Free (no ad) once the Remove Ads purchase is owned.
    func useHint() {
        guard isHumanTurn, hintsLeft > 0 else { return }
        if StoreManager.shared.hasRemoveAds {
            revealHint()
            return
        }
        guard adManager.rewardedReady, let root = topViewController() else { return }
        adManager.showRewarded(from: root) { [weak self] earned in
            guard let self = self, earned, !self.gameOver else { return }
            self.revealHint()
        }
    }

    /// Time-boost power-up: adds 30 seconds to the current turn's clock.
    /// Two uses per game. Unavailable in practice mode (no timer).
    func useTimeBoost() {
        guard !gameOver, !isPractice, isHumanTurn, timeBoostsLeft > 0 else { return }
        timeBoostsLeft -= 1
        secondsLeft += 30
    }

    private func revealHint() {
        hintsUsed += 1
        let empties = (0..<filled.count).filter {
            isLetterCell($0) && filled[$0] == nil
        }
        guard let cell = empties.randomElement() else { return }
        lockLetter(cell: cell, countsTowardBonus: false)
        showToast("Hint revealed!")
        if isBoardFull() { endGame() }
    }

    /// Rewarded "continue": the loser watches an ad, then starts the rematch
    /// with a +5 head start. Free (no ad) once Remove Ads is owned.
    func watchContinueAd(for player: Int, then: @escaping () -> Void) {
        if StoreManager.shared.hasRemoveAds {
            then()
            return
        }
        guard let root = topViewController() else { return }
        adManager.showRewarded(from: root) { earned in
            if earned { then() }
        }
    }

    // MARK: - Interstitial cadence

    /// Shows an interstitial ad every 2nd finished game — never mid-game.
    /// Suppressed entirely once the Remove Ads purchase is owned.
    func maybeShowInterstitial() {
        guard !StoreManager.shared.hasRemoveAds else { return }
        let played = UserDefaults.standard.integer(forKey: "swish_games_played") + 1
        UserDefaults.standard.set(played, forKey: "swish_games_played")
        guard played % 2 == 0, let root = topViewController() else { return }
        adManager.showInterstitial(from: root)
    }

    // MARK: - AI opponent

    private func runAI() {
        aiBusy = true
        let d = difficulty

        var moves: [(tileIndex: Int, cell: Int?)] = []

        for (ti, tile) in rack.enumerated() {
            var target: Int? = nil
            if Double.random(in: 0...1) < d.solveChance {
                let cands = (0..<filled.count).filter { i in
                    isLetterCell(i) && filled[i] == nil && solution(i) == tile.letter
                        && cellWords[i].contains(where: { aiKnown.contains($0) })
                }
                // Prefer cells in nearly-finished words
                target = cands.sorted(by: {
                    let ra = cellWords[$0].map { remainingInWord($0) }.min() ?? 99
                    let rb = cellWords[$1].map { remainingInWord($0) }.min() ?? 99
                    return ra < rb
                }).first
            } else if Double.random(in: 0...1) < d.mistakeChance {
                let wrong = (0..<filled.count).filter { i in
                    isLetterCell(i) && filled[i] == nil && solution(i) != tile.letter
                }
                target = wrong.randomElement()
            }
            moves.append((tileIndex: ti, cell: target))
        }

        executeAIMoves(moves, index: 0)
    }

    private func executeAIMoves(_ moves: [(tileIndex: Int, cell: Int?)], index: Int) {
        guard !gameOver, isAITurn else {
            aiBusy = false
            return
        }
        if index >= moves.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self else { return }
                self.aiBusy = false
                self.endTurn()
            }
            return
        }
        let m = moves[index]
        if let cell = m.cell, m.tileIndex < rack.count {
            attemptPlace(tileID: rack[m.tileIndex].id, cell: cell)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.executeAIMoves(moves, index: index + 1)
        }
    }
}

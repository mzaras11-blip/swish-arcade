import SwiftUI

struct ContentView: View {
    @State private var puzzles: [Puzzle] = []
    @State private var difficulty: Difficulty = .normal
    @State private var gameID = UUID()
    @State private var pendingMode: GameMode? = nil
    @State private var pendingDaily = false
    @State private var pendingPictureClues = true
    @State private var gameActive = false
    @State private var streak = 0
    @State private var usePictureClues = true
    @ObservedObject private var store = StoreManager.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var reminders = PlayReminder.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.menuGradient.ignoresSafeArea()
                ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        Spacer()
                        if music.enabled {
                            Slider(value: $music.volume, in: 0...1)
                                .frame(width: 120)
                                .tint(.white)
                        }
                        Button {
                            music.enabled.toggle()
                        } label: {
                            Image(systemName: music.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .accessibilityLabel(music.enabled ? "Mute music" : "Play music")
                        Button {
                            reminders.enabled.toggle()
                        } label: {
                            Image(systemName: reminders.enabled ? "bell.fill" : "bell.slash.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .accessibilityLabel(reminders.enabled ? "Turn off play reminders" : "Turn on play reminders")
                    }
                    .padding(.horizontal, 8)

                    Image("Mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 130, height: 130)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 4))
                        .shadow(radius: 10)

                    VStack(spacing: 6) {
                        Text("S.W.I.S.H - Crossword Battle ARCADE")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .foregroundColor(.white)
                        Text("CROSSWORD BATTLE")
                            .font(.title2.bold())
                            .tracking(4)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .foregroundColor(.yellow)
                        Text("Solve Words. Intercept. Score High.")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.85))
                    }

                VStack(spacing: 14) {
                    Text("SOLO VS COMPUTER")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { d in
                            Text(d.title).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)

                    Text("CLUES")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))
                    Picker("Clues", selection: $usePictureClues) {
                        Text("Pictures").tag(true)
                        Text("Text only").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)

                    Button("Start Solo Game") {
                        guard !gameActive else { return }
                        pendingMode = .solo(difficulty)
                        pendingDaily = false
                        pendingPictureClues = usePictureClues
                        gameID = UUID()
                        gameActive = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundColor(.purple)

                    Button {
                        guard !gameActive else { return }
                        pendingMode = .blitz(difficulty)
                        pendingDaily = false
                        pendingPictureClues = usePictureClues
                        gameID = UUID()
                        gameActive = true
                    } label: {
                        Label("Blitz \u{2014} 5 Min", systemImage: "bolt")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundColor(.white)

                    Button("Two Players (Pass & Play)") {
                        guard !gameActive else { return }
                        pendingMode = .passAndPlay
                        pendingDaily = false
                        pendingPictureClues = usePictureClues
                        gameID = UUID()
                        gameActive = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundColor(.white)

                    NavigationLink {
                        PlayOnlineView { difficulty in
                            // Matchmaking found no human: clearly-labeled
                            // CPU game via the existing solo engine.
                            pendingMode = .solo(difficulty)
                            pendingDaily = false
                            pendingPictureClues = usePictureClues
                            gameID = UUID()
                            gameActive = true
                        }
                    } label: {
                        Label("Play Online", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundColor(.white)

                    Button {
                        guard !gameActive else { return }
                        pendingMode = .solo(difficulty)
                        pendingDaily = true
                        pendingPictureClues = usePictureClues
                        gameID = UUID()
                        gameActive = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("Daily Puzzle")
                            if streak > 0 {
                                Text("\u{1F525} \(streak)")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundColor(.white)

                    Text("RELAXED")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))

                    Button {
                        guard !gameActive else { return }
                        pendingMode = .practice
                        pendingDaily = false
                        pendingPictureClues = usePictureClues
                        gameID = UUID()
                        gameActive = true
                    } label: {
                        Label("Practice \u{2014} No Timer", systemImage: "leaf")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundColor(.white)

                    Text("ADVANCED")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.8))

                    Button {
                        guard !gameActive else { return }
                        pendingMode = .elements
                        pendingDaily = false
                        pendingPictureClues = false // symbols are the clues
                        gameID = UUID()
                        gameActive = true
                    } label: {
                        Label("Elements — Periodic Table", systemImage: "atom")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundColor(.white)

                    HStack(spacing: 28) {
                        NavigationLink {
                            StatsView(fallbackPuzzles: puzzles)
                        } label: {
                            Label("Stats", systemImage: "chart.bar.fill")
                        }
                        NavigationLink {
                            MissionsView()
                        } label: {
                            Label("Missions", systemImage: "target")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)

                    NavigationLink("How to Play") {
                        HowToPlayView()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 8)
                }

                Spacer()

                // Store: Remove Ads (StoreKit 2 non-consumable)
                VStack(spacing: 4) {
                    if store.hasRemoveAds {
                        Label("Ad-free", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                    } else {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            if let product = store.removeAdsProduct {
                                Text("Remove Ads — \(product.displayPrice)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                            } else {
                                Text("Remove Ads")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        if let err = store.storeError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        Button("Restore Purchases") {
                            Task { await store.restore() }
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    }
                }

                Text("A brand-new puzzle generated for every game")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))

                #if canImport(GoogleMobileAds)
                if !store.hasRemoveAds {
                    BannerAdView()
                        .frame(width: 320, height: 50)
                        .padding(.bottom, 4)
                }
                #endif
            } // VStack
            .padding()
                } // ScrollView
            .navigationDestination(isPresented: $gameActive) {
                if let mode = pendingMode {
                    GameHostView(mode: mode, fallbackPuzzles: puzzles,
                                 daily: pendingDaily,
                                 pictureClues: pendingPictureClues)
                        .id(gameID)
                }
            }
            .onAppear {
                if puzzles.isEmpty {
                    puzzles = loadPuzzles() // fallback pool
                }
                PuzzleGenerator.shared.loadWords()
                PuzzlePool.shared.warmup() // start generating the first fresh puzzle
                streak = StreakStore.current().streak
            }
        }
    }
}
}

/// Deals a brand-new generated puzzle for every game, then plays it.
/// Falls back to a bundled puzzle if the word database isn't available.
struct GameHostView: View {
    let mode: GameMode
    let fallbackPuzzles: [Puzzle]
    /// When true, everyone gets the same cached puzzle all day (streak game).
    var daily: Bool = false
    /// When false, clue cells always show text (advanced mode).
    var pictureClues: Bool = true
    @State private var puzzle: Puzzle? = nil
    @State private var headStartPlayer: Int? = nil
    @State private var needsDeal = true
    @State private var generationSlow = false
    @Environment(\.dismiss) private var dismiss

    init(mode: GameMode, fallbackPuzzles: [Puzzle],
         daily: Bool = false, pictureClues: Bool = true) {
        self.mode = mode
        self.fallbackPuzzles = fallbackPuzzles
        self.daily = daily
        self.pictureClues = pictureClues
    }

    var body: some View {
        Group {
            if let puzzle = puzzle {
                GameView(
                    viewModel: GameViewModel(puzzle: puzzle, mode: mode,
                                             headStartPlayer: headStartPlayer,
                                             isDaily: daily,
                                             pictureClues: pictureClues),
                    onRematch: { dealPuzzle() },
                    onContinue: { player in dealPuzzle(headStart: player) },
                    onQuit: { dismiss() }
                )
            } else {
                ZStack {
                    LoadingView(message: generationSlow
                        ? "This is taking longer than usual…"
                        : "Generating a fresh puzzle…")
                    if generationSlow {
                        VStack {
                            Spacer()
                            VStack(spacing: 10) {
                                if !fallbackPuzzles.isEmpty {
                                    Button("Play a bundled puzzle instead") {
                                        useBundledFallback()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.white)
                                    .foregroundColor(.purple)
                                }
                                Button("Back to menu") { dismiss() }
                                    .buttonStyle(.bordered)
                                    .tint(.white)
                                    .foregroundColor(.white)
                            }
                            .padding(.bottom, 48)
                        }
                    }
                }
                .onAppear {
                    // First appearance only; rematches deal directly.
                    if needsDeal {
                        needsDeal = false
                        dealPuzzle()
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func dealPuzzle(headStart: Int? = nil) {
        headStartPlayer = headStart
        generationSlow = false
        if case .elements = mode {
            // Advanced mode: fresh element puzzle every game (no pool).
            puzzle = nil // show the loading screen while generating
            armGenerationTimeout()
            PuzzleGenerator.shared.generate(title: "Elements",
                                            using: PuzzleGenerator.elementEntries) { p in
                puzzle = p
            }
            return
        }
        if daily, let cached = DailyPuzzleStore.load() {
            // Same puzzle all day: retries chase a better score.
            puzzle = cached
        } else if let fresh = PuzzlePool.shared.take() {
            // Buffered puzzle ready: swap straight into the new game.
            if daily { DailyPuzzleStore.save(fresh) }
            puzzle = fresh
        } else if PuzzleGenerator.shared.hasWords {
            puzzle = nil // show the loading screen while generating
            armGenerationTimeout()
            PuzzleGenerator.shared.generate { p in
                if daily { DailyPuzzleStore.save(p) }
                puzzle = p
            }
        } else {
            puzzle = fallbackPuzzles.randomElement()
            // No bundled puzzles either: show the escape hatch at once
            // instead of spinning forever.
            if puzzle == nil { generationSlow = true }
        }
    }

    /// Generation watchdog: if no puzzle has arrived after a few seconds,
    /// the loading screen offers a bundled puzzle / a way back instead of
    /// spinning forever — the failure mode Kryss reviews keep reporting.
    private func armGenerationTimeout() {
        generationSlow = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if puzzle == nil { generationSlow = true }
        }
    }

    /// Loading-screen escape hatch: play one of the bundled puzzles.
    /// In Daily mode it is cached as today's puzzle, so retries stay on
    /// the same board.
    private func useBundledFallback() {
        generationSlow = false
        if let p = fallbackPuzzles.randomElement() {
            if daily { DailyPuzzleStore.save(p) }
            puzzle = p
        }
    }
}

/// Mascot loading screen with a playful animation.
/// Shown at app launch and while a fresh puzzle is being dealt.
struct LoadingView: View {
    var message: String
    @State private var animate = false

    var body: some View {
        ZStack {
            Theme.menuGradient.ignoresSafeArea()
            VStack(spacing: 22) {
                Image("Mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 4))
                    .shadow(radius: 12)
                    .offset(y: animate ? -16 : 0)
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                               value: animate)
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 14, height: 14)
                            .scaleEffect(animate ? 1.25 : 0.65)
                            .animation(
                                .easeInOut(duration: 0.45)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.15),
                                value: animate)
                    }
                }
                Text(message)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear { animate = true }
    }
}

struct HowToPlayView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How to Play")
                    .font(.largeTitle.bold())

                Group {
                    Text("You and your opponent share one crossword grid.")
                    Text("Each turn you get 5 letter tiles and 60 seconds. Tap a tile, then tap a square where you think it belongs.")
                    Text("Correct letters lock in and stay for both players. Wrong guesses bounce back \u{2014} no penalty.")
                    Text("Clues live inside the dark squares, Scandinavian-style. Some are pictures \u{2014} tap one to read the full clue.")
                    Text("Advanced players: switch Clues to \u{201C}Text only\u{201D} on the menu for the classic no-picture game.")
                    Text("Pinch or double-tap the board to zoom in on the grid.")
                }
                .font(.body)

                Text("Turn tools")
                    .font(.title2.bold())
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\u{2022} Undo takes back the last tile you placed this turn")
                    Text("\u{2022} Swap trades a selected tile for a fresh one (2 per game)")
                    Text("\u{2022} Hint reveals a correct letter (3 per game)")
                }
                .font(.body)

                Text("Scoring")
                    .font(.title2.bold())
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\u{2022} +1 for every correct letter placed")
                    Text("\u{2022} +\u{2009}word length bonus for completing a word")
                    Text("\u{2022} +5 for using all 5 tiles in one turn")
                    Text("\u{2022} Land a correct letter on a blue square to DOUBLE your whole turn")
                }
                .font(.body)

                Text("Fair play")
                    .font(.title2.bold())
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("• Unlimited games — no game boards to buy, earn, or wait for")
                    Text("• Ads never interrupt a turn, and Remove Ads is a one-time purchase — not a subscription")
                    Text("• Solo opponents are always labeled CPU — never disguised as real people")
                }
                .font(.body)

                Text("When the grid is full (or almost full with no moves left), the higher score wins.")
                    .font(.body)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Persists whether the first-launch tutorial has been shown.
enum TutorialStore {
    private static let key = "swish.seenTutorial"
    static var hasSeen: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }
}

/// First-launch onboarding: swipeable intro pages, shown once.
/// All text and design are original to S.W.I.S.H.
struct TutorialView: View {
    var onDone: () -> Void
    @State private var page = 0

    private let pages: [(icon: String, title: String, body: String)] = [
        ("square.grid.2x2.fill", "One grid, two players",
         "You and your opponent share a single crossword grid. Every word you finish scores for you — out-solve them to win the battle."),
        ("hand.tap.fill", "Your turn, your tiles",
         "Each turn you get 5 letter tiles and 60 seconds. Tap a tile, then tap the square it belongs in. Correct letters lock in for both players; wrong guesses bounce back with no penalty."),
        ("star.fill", "Score big",
         "Every correct letter scores. Finish a word for a bonus, play all 5 tiles in one turn for +5, and land a letter on a blue square to double your whole turn."),
        ("trophy.fill", "Pick your battle",
         "Take on the CPU in Solo, race the 5-minute Blitz clock, or test yourself with Elements — the periodic-table mode for advanced players. Come back daily to build your streak."),
    ]

    var body: some View {
        ZStack {
            Theme.menuGradient.ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button("Skip") { onDone() }
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding()
                TabView(selection: $page) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        VStack(spacing: 20) {
                            Image(systemName: pages[i].icon)
                                .font(.system(size: 72))
                                .foregroundColor(.yellow)
                            Text(pages[i].title)
                                .font(.title.bold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Text(pages[i].body)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                Button(page == pages.count - 1 ? "Start Playing" : "Next") {
                    if page == pages.count - 1 {
                        onDone()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .foregroundColor(.purple)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Stats & Missions

struct StatsView: View {
    private let s = StatsStore.summary()
    private let recent = RecentGamesStore.list()
    let fallbackPuzzles: [Puzzle]

    var body: some View {
        List {
            Section("Solo vs CPU") {
                statRow("Wins", "\(s.wins)")
                statRow("Losses", "\(s.losses)")
                statRow("Draws", "\(s.draws)")
                statRow("Win rate", String(format: "%.0f%%", s.winRate * 100))
            }
            Section("Streak calendar") {
                StreakCalendarView()
            }
            Section("Last 10 games") {
                if s.last10.isEmpty {
                    Text("No games yet \u{2014} go play!")
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ForEach(0..<s.last10.count, id: \.self) { i in
                            Circle()
                                .fill(formColor(s.last10[i]))
                                .frame(width: 22, height: 22)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Averages") {
                statRow("Letters per turn",
                        String(format: "%.1f", s.avgLettersPerTurn))
            }
            Section("Pass & Play") {
                statRow("Games played", "\(s.localGames)")
            }
            Section("Recent games") {
                if recent.isEmpty {
                    Text("No finished games yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recent, id: \.id) { g in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.resultText)
                                    .font(.headline)
                                Text("\(g.modeLabel) \u{00B7} \(g.scores[0])\u{2013}\(g.scores[1])")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            NavigationLink("Rematch") {
                                GameHostView(mode: g.mode,
                                             fallbackPuzzles: fallbackPuzzles,
                                             pictureClues: g.pictureClues)
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Stats")
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).bold()
        }
    }

    private func formColor(_ r: Int) -> Color {
        if r > 0 { return .green }
        if r < 0 { return .red }
        return .gray
    }
}

/// Month grid marking the days the daily puzzle was completed.
/// Today gets a ring; completed days get a green checkmark.
struct StreakCalendarView: View {
    @State private var monthOffset = 0

    private var calendar: Calendar { Calendar.current }

    private var monthDate: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var title: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: monthDate)
    }

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var completed: Set<String> { Set(StreakStore.completionDays()) }

    /// Day numbers for the grid; nil = leading blank (weeks start Sunday).
    private var cells: [Int?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthDate),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month],
                                                                              from: monthDate))
        else { return [] }
        let leading = calendar.component(.weekday, from: firstOfMonth) - 1
        var cells: [Int?] = Array(repeating: nil, count: leading)
        cells += range.map { Optional($0) }
        return cells
    }

    private func dayString(_ day: Int) -> String {
        String(format: "%04d-%02d-%02d",
               calendar.component(.year, from: monthDate),
               calendar.component(.month, from: monthDate),
               day)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { monthOffset -= 1 } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(title)
                    .font(.headline)
                Spacer()
                Button { monthOffset += 1 } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(monthOffset >= 0)
                .opacity(monthOffset >= 0 ? 0.3 : 1)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                      spacing: 4) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { d in
                    Text(d)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] {
                        let ds = dayString(day)
                        let isToday = ds == todayString
                        let done = completed.contains(ds)
                        ZStack {
                            if isToday {
                                Circle().stroke(Color.accentColor, lineWidth: 2)
                            } else if done {
                                Circle().fill(Color.green.opacity(0.22))
                            }
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.caption2).bold()
                                    .foregroundColor(.green)
                            } else {
                                Text("\(day)")
                                    .font(.caption)
                                    .foregroundColor(isToday ? .primary : .secondary)
                            }
                        }
                        .frame(width: 30, height: 30)
                    } else {
                        Color.clear.frame(width: 30, height: 30)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Daily puzzle completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

struct MissionsView: View {
    private let missions = MissionStore.todayMissions()

    var body: some View {
        List(missions) { m in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(m.title)
                        .font(.headline)
                    Spacer()
                    if m.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                ProgressView(value: Double(m.progress), total: Double(m.target))
                Text("\(m.progress) / \(m.target)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Today's Missions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GameOverView: View {
    let viewModel: GameViewModel
    let onRematch: () -> Void
    let onContinue: (Int) -> Void
    let onQuit: () -> Void
    @ObservedObject private var adManager = AdManager.shared
    @ObservedObject private var store = StoreManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image("Mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
                .shadow(radius: 6)
            if viewModel.isPractice {
                Text("Practice Complete!")
                    .font(.largeTitle.bold())
                Text("\u{1F3C6} \(viewModel.scores[0]) points \u{00B7} \(viewModel.wordsCompleted[0]) words")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                // Single-player stat summary (no opponent in practice).
                VStack(spacing: 6) {
                    practiceRow("Words completed", "\(viewModel.wordsCompleted[0])")
                    practiceRow("Letters placed", "\(viewModel.lettersPlaced[0])")
                    practiceRow("Avg letters / turn",
                                String(format: "%.1f", viewModel.avgLettersPerTurn[0]))
                    practiceRow("Clean sweep turns",
                                String(format: "%.0f%%", viewModel.cleanSweepRate[0] * 100))
                }
                .padding(.vertical, 4)
            } else {
                Text("Game Over")
                    .font(.largeTitle.bold())

                if let w = viewModel.winner {
                    Text("\u{1F3C6} \(viewModel.playerNames[w]) wins!")
                        .font(.title2.bold())
                } else {
                    Text("It's a tie!")
                        .font(.title2.bold())
                }

                // Head-to-head stat comparison (Kryss-style results screen)
                VStack(spacing: 6) {
                    HStack {
                        Text(viewModel.playerNames[0])
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Spacer().frame(width: 110)
                        Text(viewModel.playerNames[1])
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    resultRow("Points", "\(viewModel.scores[0])", "\(viewModel.scores[1])")
                    resultRow("Avg letters / turn",
                              String(format: "%.1f", viewModel.avgLettersPerTurn[0]),
                              String(format: "%.1f", viewModel.avgLettersPerTurn[1]))
                    resultRow("Clean sweep turns",
                              String(format: "%.0f%%", viewModel.cleanSweepRate[0] * 100),
                              String(format: "%.0f%%", viewModel.cleanSweepRate[1] * 100))
                    resultRow("Words completed",
                              "\(viewModel.wordsCompleted[0])",
                              "\(viewModel.wordsCompleted[1])")
                    resultRow("Letters placed",
                              "\(viewModel.lettersPlaced[0])",
                              "\(viewModel.lettersPlaced[1])")
                }
                .padding(.vertical, 4)

                // Rewarded continue: the loser can watch an ad for a +5 head start
                // in the rematch. Free when Remove Ads is owned.
                if let loser = viewModel.loser {
                    let adNote = store.hasRemoveAds ? "" : " (\u{1F4FA} ad)"
                    Button("\(viewModel.playerNames[loser]): continue +5\(adNote)") {
                        viewModel.watchContinueAd(for: loser) {
                            onContinue(loser)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button("Rematch") { onRematch() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Main Menu") { onQuit() }
                .buttonStyle(.bordered)
        }
        .padding()
        .onAppear {
            viewModel.maybeShowInterstitial()
        }
        .fullScreenCover(isPresented: $adManager.showingMockAd) {
            MockAdView(title: adManager.mockAdTitle)
        }
    }

    private func practiceRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
        .padding(.horizontal, 40)
    }

    private func resultRow(_ label: String, _ left: String, _ right: String) -> some View {
        HStack {
            Text(left)
                .bold()
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110)
            Text(right)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

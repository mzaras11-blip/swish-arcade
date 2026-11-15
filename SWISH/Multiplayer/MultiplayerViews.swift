import SwiftUI

// MARK: - S.W.I.S.H async multiplayer: SwiftUI
//
// Play Online hub, matchmaking (30s -> clearly-labeled CPU fallback),
// match list, friend search, challenge inbox, and the online turn screen.
// All game outcomes come from the server via MultiplayerBackend; this
// layer only renders state and requests actions.

// MARK: - Session

/// App-wide multiplayer state. Sign-in is anonymous (Firebase Auth);
/// the profile (with the claimed username) drives every online screen.
@MainActor
final class MultiplayerSession: ObservableObject {
    static let shared = MultiplayerSession()

    let backend: MultiplayerBackend = FirebaseBackend()

    @Published var profile: MPPlayerProfile?
    @Published var usernameDraft = ""
    @Published var isWorking = false
    @Published var errorMessage: String?

    private init() {}

    var isSignedIn: Bool { profile != nil }
    var hasUsername: Bool { !(profile?.username ?? "").isEmpty }
    var uid: String? { profile?.id }

    func ensureSignedIn() async {
        if profile != nil { return }
        isWorking = true
        defer { isWorking = false }
        do {
            profile = try await backend.signIn()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func claimUsername() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            profile = try await backend.claimUsername(usernameDraft)
            usernameDraft = ""
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

// MARK: - Entry point

/// "Play Online" destination. Gates on sign-in, then username claim,
/// then the hub. `onPlayCPU` starts a local solo-vs-CPU game when
/// matchmaking finds no human (opponent always labeled "CPU").
struct PlayOnlineView: View {
    @StateObject private var session = MultiplayerSession.shared
    let onPlayCPU: (Difficulty) -> Void

    var body: some View {
        Group {
            if !session.isSignedIn {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Signing you in…")
                        .foregroundColor(.secondary)
                    if let e = session.errorMessage {
                        Text(e).font(.caption).foregroundColor(.red)
                        Button("Retry") { Task { await session.ensureSignedIn() } }
                            .buttonStyle(.bordered)
                    }
                }
            } else if !session.hasUsername {
                UsernameClaimView()
            } else {
                OnlineHubView(onPlayCPU: onPlayCPU)
            }
        }
        .navigationTitle("Play Online")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.ensureSignedIn() }
    }
}

struct UsernameClaimView: View {
    @StateObject private var session = MultiplayerSession.shared

    var body: some View {
        Form {
            Section("Pick a username") {
                TextField("3–16 letters, numbers, _", text: $session.usernameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Claim Username") {
                    Task { await session.claimUsername() }
                }
                .disabled(session.usernameDraft.count < 3 || session.isWorking)
            }
            Section {
                Text("This is how opponents will see you. Names are unique — first to claim one keeps it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let e = session.errorMessage {
                Text(e).font(.caption).foregroundColor(.red)
            }
        }
        .navigationTitle("Choose a Username")
    }
}

// MARK: - Hub

struct OnlineHubView: View {
    @StateObject private var session = MultiplayerSession.shared
    let onPlayCPU: (Difficulty) -> Void
    @State private var challengeCount = 0

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text("@\(session.profile?.username ?? "")")
                            .font(.headline)
                        if let p = session.profile {
                            Text("W \(p.wins) · L \(p.losses) · D \(p.draws)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Play") {
                NavigationLink {
                    MatchmakingView(onPlayCPU: onPlayCPU)
                } label: {
                    Label("Find a Random Opponent", systemImage: "shuffle")
                }
                NavigationLink {
                    MatchListView()
                } label: {
                    Label("My Matches", systemImage: "list.bullet")
                }
            }

            Section("Friends") {
                NavigationLink {
                    FriendSearchView()
                } label: {
                    Label("Find Friend by Username", systemImage: "magnifyingglass")
                }
                NavigationLink {
                    ChallengeInboxView()
                } label: {
                    Label("Challenge Inbox", systemImage: "envelope")
                }
                .badge(challengeCount)
            }

            Section("How it works") {
                Text("Turns last 24 hours — play at your own pace, like Kryss. If no human opponent is waiting, you can play a clearly-labeled CPU game instead. Bots are never disguised as people.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Play Online")
        .task { await loadInboxCount() }
    }

    private func loadInboxCount() async {
        if let list = try? await session.backend.myChallenges() {
            challengeCount = list.count
        }
    }
}

// MARK: - Matchmaking

struct MatchmakingView: View {
    @StateObject private var session = MultiplayerSession.shared
    let onPlayCPU: (Difficulty) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var activeMatch: MPMatch?
    @State private var searching = true
    @State private var timedOut = false
    @State private var difficulty: Difficulty = .normal
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            if searching {
                ProgressView()
                    .scaleEffect(1.4)
                Text("Looking for an opponent…")
                    .font(.headline)
                Text("Waiting up to 30 seconds for another player.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if timedOut {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No players waiting right now.")
                    .font(.headline)
                Text("You can play a clearly-labeled CPU game instead — it is never presented as a human opponent.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Picker("CPU difficulty", selection: $difficulty) {
                    ForEach(Difficulty.allCases) { d in
                        Text(d.title).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)

                Button("Play vs CPU (\(difficulty.title))") {
                    // The ONLY label a bot opponent may ever carry.
                    let req = BotBackfill.requestCPUGame(difficulty: difficulty)
                    dismiss()
                    onPlayCPU(req.difficulty)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Keep Waiting") {
                    Task { await search() }
                }
                .buttonStyle(.bordered)
            }
            if let e = errorMessage {
                Text(e).font(.caption).foregroundColor(.red)
                Button("Try Again") { Task { await search() } }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .navigationTitle("Find Match")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeMatch) { match in
            OnlineMatchView(match: match)
        }
        .task { await search() }
    }

    private func search() async {
        searching = true
        timedOut = false
        errorMessage = nil
        defer { searching = false }
        do {
            // Explicit timeout: the protocol declares the parameter without
            // a default, so it must be passed at the call site.
            switch try await session.backend.findMatch(timeout: MPConfig.matchmakingTimeout) {
            case .matched(let m):
                activeMatch = m
            case .timedOut:
                timedOut = true
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Match list

struct MatchListView: View {
    @StateObject private var session = MultiplayerSession.shared
    @State private var matches: [MPMatch] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading matches…")
            } else if matches.isEmpty {
                VStack(spacing: 12) {
                    Text("No matches yet.")
                        .foregroundColor(.secondary)
                    Text("Find a random opponent or challenge a friend to start your first battle.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List(matches) { m in
                    NavigationLink {
                        OnlineMatchView(match: m)
                    } label: {
                        MatchRowView(match: m, uid: session.uid ?? "")
                    }
                }
                .refreshable { await load() }
            }
            if let e = errorMessage {
                Text(e).font(.caption).foregroundColor(.red).padding()
            }
        }
        .navigationTitle("My Matches")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            matches = try await session.backend.myMatches()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct MatchRowView: View {
    let match: MPMatch
    let uid: String

    private var me: Int { match.playerIndex(of: uid) ?? 0 }
    private var oppName: String { match.opponent(of: uid)?.username ?? "opponent" }
    private func score(_ i: Int) -> Int { match.scores.indices.contains(i) ? match.scores[i] : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("vs \(oppName)")
                    .font(.headline)
                Spacer()
                Text("\(score(me))–\(score(1 - me))")
                    .font(.headline.monospacedDigit())
            }
            Text(statusText)
                .font(.subheadline)
                .foregroundColor(statusColor)
            if match.status == .active, let d = match.turnDeadline {
                Text("Turn ends \(d, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch match.status {
        case .finished:
            if match.winnerIndex == nil { return "Tie game" }
            return match.winnerIndex == me ? "You won! 🏆" : "You lost"
        case .active:
            return match.currentPlayer == me ? "Your turn" : "Waiting on \(oppName)"
        case .waiting:
            return "Starting…"
        }
    }

    private var statusColor: Color {
        switch match.status {
        case .finished:
            return match.winnerIndex == me ? .green : .secondary
        case .active:
            return match.currentPlayer == me ? .accentColor : .secondary
        case .waiting:
            return .secondary
        }
    }
}

// MARK: - Friend search

struct FriendSearchView: View {
    @StateObject private var session = MultiplayerSession.shared
    @State private var query = ""
    @State private var result: MPPlayerProfile?
    @State private var searched = false
    @State private var challengeSent = false
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Exact username") {
                TextField("username", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Search") {
                    Task { await search() }
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            if searched {
                Section {
                    if let p = result {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(p.username)")
                                    .font(.headline)
                                Text("W \(p.wins) · L \(p.losses) · D \(p.draws)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if challengeSent {
                                Label("Sent", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Button("Challenge") {
                                    Task { await challenge(p) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(working)
                            }
                        }
                    } else {
                        Text("No player with that username.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            if let e = errorMessage {
                Text(e).font(.caption).foregroundColor(.red)
            }
        }
        .navigationTitle("Find Friend")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func search() async {
        working = true
        defer { working = false }
        errorMessage = nil
        challengeSent = false
        do {
            result = try await session.backend.searchUser(username: query)
            searched = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func challenge(_ p: MPPlayerProfile) async {
        working = true
        defer { working = false }
        do {
            _ = try await session.backend.challengeUser(uid: p.id)
            challengeSent = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Challenge inbox

struct ChallengeInboxView: View {
    @StateObject private var session = MultiplayerSession.shared
    @State private var challenges: [MPChallenge] = []
    @State private var activeMatch: MPMatch?
    @State private var loading = true
    @State private var workingId: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading challenges…")
            } else if challenges.isEmpty {
                Text("No challenges waiting.\nAsk a friend to search your username!")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                List(challenges) { c in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(c.fromUsername) challenged you!")
                                .font(.headline)
                            Text("Expires \(c.expiresAt, style: .relative)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Button("Accept") {
                                Task { await respond(c, accept: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(workingId != nil)
                            Button("Decline") {
                                Task { await respond(c, accept: false) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(workingId != nil)
                            if workingId == c.id { ProgressView() }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .refreshable { await load() }
            }
            if let e = errorMessage {
                Text(e).font(.caption).foregroundColor(.red).padding()
            }
        }
        .navigationTitle("Challenge Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeMatch) { match in
            OnlineMatchView(match: match)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            challenges = try await session.backend.myChallenges()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func respond(_ c: MPChallenge, accept: Bool) async {
        workingId = c.id
        defer { workingId = nil }
        do {
            if let m = try await session.backend.respondToChallenge(id: c.id, accept: accept) {
                activeMatch = m
            } else {
                challenges.removeAll { $0.id == c.id }
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Online turn screen

/// View model for one async match. Holds the authoritative server match
/// plus my in-progress placements for this turn. Scoring is computed
/// server-side on submitTurn — what you see here is display only.
@MainActor
final class OnlineMatchViewModel: ObservableObject {
    @Published var match: MPMatch
    /// cell -> letter for my not-yet-submitted placements this turn.
    @Published var placements: [Int: String] = [:]
    /// Cells in placement order (drives undo).
    @Published var placementOrder: [Int] = []
    /// cell -> rack index consumed by that placement.
    @Published var placementRack: [Int: Int] = [:]
    @Published var usedRack: Set<Int> = []
    @Published var selectedRack: Int?
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var showForfeitConfirm = false
    @Published var toast: String?

    let uid: String
    private let backend: MultiplayerBackend

    init(match: MPMatch, uid: String, backend: MultiplayerBackend) {
        self.match = match
        self.uid = uid
        self.backend = backend
    }

    var myIndex: Int { match.playerIndex(of: uid) ?? 0 }
    var oppIndex: Int { 1 - myIndex }
    var isMyTurn: Bool { match.status == .active && match.currentPlayer == myIndex }
    var isFinished: Bool { match.status == .finished }

    var rack: [String] {
        guard match.currentRacks.indices.contains(myIndex) else { return [] }
        return match.currentRacks[myIndex]
    }

    func name(_ i: Int) -> String {
        if i == myIndex { return "You" }
        return match.usernames.indices.contains(i) ? match.usernames[i] : "Opponent"
    }

    func score(_ i: Int) -> Int {
        match.scores.indices.contains(i) ? match.scores[i] : 0
    }

    func isLetterCell(_ i: Int) -> Bool {
        match.puzzle.cells.indices.contains(i) && match.puzzle.cells[i].k == "l"
    }

    func isBonus(_ i: Int) -> Bool {
        match.puzzle.cells.indices.contains(i) && match.puzzle.cells[i].b == true
    }

    /// Who locked this cell on the server (nil = empty). My in-progress
    /// placements are NOT here yet — see `myLetter(at:)`.
    func serverFilledBy(_ i: Int) -> Int? {
        guard match.filledBy.indices.contains(i) else { return nil }
        return match.filledBy[i]
    }

    func myLetter(at cell: Int) -> String? { placements[cell] }

    func clueText(_ i: Int) -> String {
        guard match.puzzle.cells.indices.contains(i) else { return "" }
        let cell = match.puzzle.cells[i]
        var parts: [String] = []
        if let a = cell.ca { parts.append("→ " + a) }
        if let d = cell.cd { parts.append("↓ " + d) }
        return parts.joined(separator: "\n")
    }

    var deadlineText: String? {
        guard match.status == .active, let d = match.turnDeadline else { return nil }
        let s = Int(d.timeIntervalSinceNow)
        if s <= 0 { return "Turn time expired" }
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m left on this turn" : "\(m)m left on this turn"
    }

    var resultText: String {
        guard let w = match.winnerIndex else { return "It's a tie!" }
        return w == myIndex ? "🏆 You win!" : "\(name(oppIndex)) wins"
    }

    // MARK: - Placement (tap tile, tap cell — mirrors solo mode)

    func tapRack(_ i: Int) {
        guard isMyTurn, !isSubmitting else { return }
        guard rack.indices.contains(i), !usedRack.contains(i) else { return }
        selectedRack = (selectedRack == i) ? nil : i
    }

    func tapCell(_ cell: Int) {
        guard isMyTurn, !isSubmitting else { return }
        guard isLetterCell(cell) else { return }
        // Tapping my own in-progress tile removes it (quick undo).
        if placements[cell] != nil {
            removePlacement(cell: cell)
            return
        }
        // Server-locked cells are untouchable.
        if serverFilledBy(cell) != nil { return }
        guard let r = selectedRack, rack.indices.contains(r), !usedRack.contains(r) else { return }
        let letter = rack[r]
        // Local UX mirrors solo mode: wrong guesses bounce back. The
        // client holds the full puzzle, but the server still validates
        // authoritatively on submit.
        guard letter == match.puzzle.cells[cell].s else {
            showToast("That letter doesn't fit there")
            return
        }
        placements[cell] = letter
        placementOrder.append(cell)
        placementRack[cell] = r
        usedRack.insert(r)
        selectedRack = nil
    }

    private func removePlacement(cell: Int) {
        placements.removeValue(forKey: cell)
        placementOrder.removeAll { $0 == cell }
        if let r = placementRack.removeValue(forKey: cell) {
            usedRack.remove(r)
        }
        if selectedRack != nil { selectedRack = nil }
    }

    func undoLast() {
        guard isMyTurn, !isSubmitting, let cell = placementOrder.popLast() else { return }
        removePlacement(cell: cell)
    }

    // MARK: - Server actions

    /// Submits my placements (empty = pass). The server validates and
    /// recomputes the score; the returned match is authoritative.
    func endTurn() async {
        guard isMyTurn, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let turn = MPTurn(
            matchId: match.id,
            playerIndex: myIndex,
            turnNumber: match.turnNumber,
            placements: placementOrder.map { MPPlacement(cell: $0, letter: placements[$0] ?? "") },
            scoreDelta: nil,
            wordsCompleted: nil
        )
        do {
            match = try await backend.submitTurn(turn)
            placements = [:]
            placementOrder = []
            placementRack = [:]
            usedRack = []
            selectedRack = nil
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refresh() async {
        do {
            match = try await backend.getMatch(id: match.id)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func forfeit() async {
        do {
            match = try await backend.forfeit(matchId: match.id)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if toast == text { toast = nil }
        }
    }
}

struct OnlineMatchView: View {
    @StateObject private var viewModel: OnlineMatchViewModel
    @Environment(\.dismiss) private var dismiss

    init(match: MPMatch) {
        let s = MultiplayerSession.shared
        _viewModel = StateObject(wrappedValue: OnlineMatchViewModel(
            match: match,
            uid: s.profile?.id ?? "",
            backend: s.backend
        ))
    }

    var body: some View {
        ZStack {
            Theme.gameBackground.ignoresSafeArea()
            GeometryReader { geo in
                let cols = CGFloat(viewModel.match.puzzle.cols)
                let cellSize = (geo.size.width - 32 - (cols - 1) * 3) / cols
                ScrollView {
                    VStack(spacing: 10) {
                        // Score header
                        HStack {
                            onlineScoreColumn(name: viewModel.name(viewModel.myIndex),
                                              score: viewModel.score(viewModel.myIndex),
                                              active: viewModel.isMyTurn)
                            Spacer()
                            VStack(spacing: 2) {
                                if viewModel.isFinished {
                                    Text(viewModel.resultText)
                                        .font(.headline)
                                } else {
                                    Text(viewModel.isMyTurn ? "Your turn" : "Waiting on \(viewModel.name(viewModel.oppIndex))")
                                        .font(.headline)
                                    if let d = viewModel.deadlineText {
                                        Text(d)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            onlineScoreColumn(name: viewModel.name(viewModel.oppIndex),
                                              score: viewModel.score(viewModel.oppIndex),
                                              active: !viewModel.isMyTurn && !viewModel.isFinished)
                        }
                        .padding(.horizontal)

                        // Board
                        OnlineBoardView(viewModel: viewModel, cellSize: cellSize)

                        // Rack (my turn only)
                        if viewModel.isMyTurn && !viewModel.isFinished {
                            OnlineRackView(viewModel: viewModel)
                        }

                        // Actions
                        if !viewModel.isFinished {
                            VStack(spacing: 8) {
                                HStack(spacing: 12) {
                                    Button("Undo") { viewModel.undoLast() }
                                        .buttonStyle(.bordered)
                                        .disabled(!viewModel.isMyTurn || viewModel.placementOrder.isEmpty)
                                    Button("Refresh") {
                                        Task { await viewModel.refresh() }
                                    }
                                    .buttonStyle(.bordered)
                                    Button("Forfeit") { viewModel.showForfeitConfirm = true }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                }
                                Button(viewModel.placementOrder.isEmpty ? "Pass Turn" : "End Turn") {
                                    Task { await viewModel.endTurn() }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(!viewModel.isMyTurn || viewModel.isSubmitting)
                                .frame(maxWidth: .infinity)
                                if viewModel.isSubmitting {
                                    ProgressView("Submitting…")
                                }
                            }
                        } else {
                            Button("Back to Matches") { dismiss() }
                                .buttonStyle(.borderedProminent)
                        }

                        if let e = viewModel.errorMessage {
                            Text(e)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        Text("Turns are checked by the server — scores can't be faked.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .overlay(alignment: .top) {
                if let toast = viewModel.toast {
                    Text(toast)
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        .padding(.top, 8)
                }
            }
        }
        .navigationTitle("vs \(viewModel.name(viewModel.oppIndex))")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Forfeit this match?", isPresented: $viewModel.showForfeitConfirm) {
            Button("Forfeit", role: .destructive) {
                Task { await viewModel.forfeit() }
            }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Your opponent wins by forfeit.")
        }
        .task { await viewModel.refresh() }
    }

    private func onlineScoreColumn(name: String, score: Int, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(score)")
                .font(.system(size: 32, weight: .bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(10)
    }
}

struct OnlineBoardView: View {
    @ObservedObject var viewModel: OnlineMatchViewModel
    let cellSize: CGFloat
    @State private var cluePopup: String?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellSize), spacing: 3),
              count: viewModel.match.puzzle.cols)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(0..<viewModel.match.puzzle.cells.count, id: \.self) { i in
                onlineCell(i)
            }
        }
        .alert("Clue", isPresented: .constant(cluePopup != nil)) {
            Button("OK") { cluePopup = nil }
        } message: {
            Text(cluePopup ?? "")
        }
    }

    @ViewBuilder
    private func onlineCell(_ i: Int) -> some View {
        let cell = viewModel.match.puzzle.cells[i]
        Group {
            switch cell.k {
            case "x":
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black)
            case "c":
                Button {
                    cluePopup = viewModel.clueText(i)
                } label: {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [Color.yellow.opacity(0.55),
                                         Color.orange.opacity(0.45)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        VStack(spacing: 0) {
                            Text(cell.ca != nil ? "→" : "↓")
                                .font(.system(size: cellSize * 0.28, weight: .bold))
                            Text(String((cell.ca ?? cell.cd ?? "").prefix(24)))
                                .font(.system(size: cellSize * 0.16))
                                .lineLimit(3)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(2)
                    }
                }
                .buttonStyle(.plain)
            default:
                Button {
                    viewModel.tapCell(i)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(onlineCellFill(i))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(onlineCellBorder(i), lineWidth: onlineCellBorderWidth(i))
                            )
                        if let letter = viewModel.myLetter(at: i) {
                            // My in-progress placement: accent tint, not yet locked.
                            Text(letter)
                                .font(.system(size: cellSize * 0.5, weight: .black))
                                .foregroundColor(.accentColor)
                        } else if viewModel.serverFilledBy(i) != nil,
                                  let s = cell.s {
                            // Server-locked letter, colored by who placed it.
                            Text(s)
                                .font(.system(size: cellSize * 0.5, weight: .black))
                                .foregroundColor(.white)
                                .shadow(radius: 1)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if viewModel.myLetter(at: i) != nil {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 9, height: 9)
                                .padding(4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isMyTurn)
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    private func onlineCellFill(_ i: Int) -> AnyShapeStyle {
        if let by = viewModel.serverFilledBy(i) {
            return AnyShapeStyle(Theme.playerGradient(by))
        }
        if viewModel.myLetter(at: i) != nil {
            return AnyShapeStyle(Color.accentColor.opacity(0.25))
        }
        if viewModel.isBonus(i) {
            return AnyShapeStyle(Theme.bonusGradient)
        }
        return AnyShapeStyle(Color(.systemBackground))
    }

    private func onlineCellBorder(_ i: Int) -> Color {
        if viewModel.serverFilledBy(i) != nil { return .clear }
        return viewModel.isBonus(i) ? .blue : Color(.systemGray4)
    }

    private func onlineCellBorderWidth(_ i: Int) -> CGFloat {
        if viewModel.serverFilledBy(i) != nil { return 0 }
        return viewModel.isBonus(i) ? 2 : 1
    }
}

struct OnlineRackView: View {
    @ObservedObject var viewModel: OnlineMatchViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<viewModel.rack.count, id: \.self) { i in
                let letter = viewModel.rack[i]
                let used = viewModel.usedRack.contains(i)
                let selected = viewModel.selectedRack == i
                Text(letter)
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(selected ? Theme.tileSelectedGradient
                                         : LinearGradient(colors: [.white, Color(.systemGray5)],
                                                          startPoint: .top, endPoint: .bottom))
                    .foregroundColor(selected ? .white : .primary)
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                    .scaleEffect(selected ? 1.08 : 1.0)
                    .opacity(used ? 0.25 : 1.0)
                    .onTapGesture { viewModel.tapRack(i) }
            }
        }
        .padding(.vertical, 6)
    }
}

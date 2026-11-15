import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme

enum Theme {
    static func playerGradient(_ p: Int?) -> LinearGradient {
        let colors: [Color] = (p == 1)
            ? [.orange, .pink]
            : [.green, .teal]
        return LinearGradient(colors: colors,
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let menuGradient = LinearGradient(
        colors: [Color(red: 0.22, green: 0.32, blue: 0.95),
                 Color(red: 0.52, green: 0.28, blue: 0.92),
                 Color(red: 0.92, green: 0.32, blue: 0.58)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gameBackground = LinearGradient(
        colors: [Color(.systemBackground), Color.blue.opacity(0.10)],
        startPoint: .top, endPoint: .bottom)

    static let bonusGradient = LinearGradient(
        colors: [.blue, .cyan],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let tileSelectedGradient = LinearGradient(
        colors: [.orange, .pink],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Drag and drop

/// Accepts tile drags onto board cells.
struct TileDropDelegate: DropDelegate {
    let cell: Int
    let viewModel: GameViewModel

    func validateDrop(info: DropInfo) -> Bool {
        viewModel.isHumanTurn && !viewModel.gameOver
            && viewModel.isLetterCell(cell) && viewModel.filled[cell] == nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        for provider in info.itemProviders(for: [UTType.text]) {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier,
                              options: nil) { item, _ in
                guard let str = item as? String,
                      let id = UUID(uuidString: str) else { return }
                DispatchQueue.main.async {
                    self.viewModel.attemptPlace(tileID: id, cell: self.cell)
                    self.viewModel.dropTarget = nil
                }
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        if validateDrop(info: info) { viewModel.dropTarget = cell }
    }

    func dropExited(info: DropInfo) {
        if viewModel.dropTarget == cell { viewModel.dropTarget = nil }
    }
}

struct GameView: View {
    @ObservedObject var viewModel: GameViewModel
    @ObservedObject private var adManager = AdManager.shared
    let onRematch: () -> Void
    let onContinue: (Int) -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            GeometryReader { geo in
            let cols = CGFloat(viewModel.puzzle.cols)
            let cellSize = (geo.size.width - 32 - (cols - 1) * 3) / cols

            ScrollView {
            VStack(spacing: 10) {                // Score header
                if viewModel.isPractice {
                    // Practice: single player, untimed, no opponent.
                    HStack {
                        scoreColumn(name: viewModel.playerNames[0],
                                    score: viewModel.scores[0],
                                    active: !viewModel.gameOver)
                        Spacer()
                        VStack(spacing: 2) {
                            Text("\u{1F33F} Practice")
                                .font(.headline)
                            Text("untimed \u{00B7} no opponent")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("\(viewModel.wordsCompleted[0])")
                                .font(.system(size: 32, weight: .bold))
                            Text("words")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .padding(.horizontal)
                } else {
                    HStack {
                        scoreColumn(name: viewModel.playerNames[0],
                                    score: viewModel.scores[0],
                                    active: viewModel.currentPlayer == 0 && !viewModel.gameOver)
                        Spacer()
                        VStack(spacing: 2) {
                            if viewModel.isBlitz {
                                Text(viewModel.blitzClock)
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundColor(viewModel.blitzSecondsLeft <= 30 ? .red : .primary)
                                Text("Turn \(viewModel.turnNumber) \u{00B7} \(viewModel.secondsLeft)s this turn")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(viewModel.secondsLeft)s")
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundColor(viewModel.secondsLeft <= 10 ? .red : .primary)
                                HStack(spacing: 6) {
                                    Text("Turn \(viewModel.turnNumber)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if viewModel.blueHit {
                                        Text("\u{00D7}2")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue)
                                            .cornerRadius(8)
                                    }
                                }
                                Text(viewModel.isAITurn ? "CPU thinking\u{2026}" : "\(viewModel.playerNames[viewModel.currentPlayer])'s turn")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        scoreColumn(name: viewModel.playerNames[1],
                                    score: viewModel.scores[1],
                                    active: viewModel.currentPlayer == 1 && !viewModel.gameOver)
                    }
                    .padding(.horizontal)
                }

                // Board (pinch or double-tap to zoom)
                ZoomableBoardView(viewModel: viewModel, cellSize: cellSize)

                // Rack
                RackView(viewModel: viewModel)

                // Actions
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button(hintLabel) {
                            viewModel.useHint()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isHumanTurn || viewModel.gameOver
                                  || viewModel.hintsLeft <= 0
                                  || (!StoreManager.shared.hasRemoveAds && !viewModel.adManager.rewardedReady))

                        Button("Undo") {
                            viewModel.undoLast()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isHumanTurn || viewModel.gameOver
                                  || viewModel.turnCells.isEmpty)

                        if viewModel.swapPicking {
                            Button("Swap \(viewModel.swapPicked.count)/2") {
                                viewModel.confirmSwap()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.swapPicked.count != 2)
                            Button("Cancel") {
                                viewModel.cancelSwapPicking()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button(swapLabel) {
                                viewModel.startSwapPicking()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.isHumanTurn || viewModel.gameOver
                                      || viewModel.discardsLeft <= 0)
                        }

                        Button(boostLabel) {
                            viewModel.useTimeBoost()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isHumanTurn || viewModel.gameOver
                                  || viewModel.timeBoostsLeft <= 0
                                  || viewModel.isPractice)
                    }

                    Button(viewModel.isPractice ? "New Tiles" : (viewModel.isAITurn ? "CPU is playing\u{2026}" : "End Turn")) {
                        viewModel.endTurn()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isHumanTurn || viewModel.gameOver)
                    .frame(maxWidth: .infinity)

                    Button("Forfeit") {
                        viewModel.showForfeitConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(viewModel.gameOver)
                    .alert("Forfeit this game?", isPresented: $viewModel.showForfeitConfirm) {
                        Button("Forfeit", role: .destructive) { viewModel.forfeit() }
                        Button("Keep playing", role: .cancel) { }
                    } message: {
                        Text("This will count as a loss.")
                    }
                }
                .padding(.bottom, 4)
            }
            } // ScrollView
            .padding(.horizontal, 16)
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
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.toast)
        }
        .navigationTitle(viewModel.puzzle.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Quit") { onQuit() }
            }
        }
        .alert(item: $viewModel.popup) { p in
            Alert(title: Text(p.title), message: Text(p.text), dismissButton: .default(Text("OK")))
        }
        .fullScreenCover(isPresented: $viewModel.gameOver) {
            GameOverView(viewModel: viewModel, onRematch: onRematch,
                         onContinue: onContinue, onQuit: onQuit)
        }
        .fullScreenCover(isPresented: $adManager.showingMockAd) {
            MockAdView(title: adManager.mockAdTitle)
        }
        } // ZStack
        .background(Theme.gameBackground.ignoresSafeArea())
    }

    private var hintLabel: String {
        let suffix = StoreManager.shared.hasRemoveAds ? "" : " (\u{1F4FA} ad)"
        return "Hint\(suffix) \u{00B7} \(viewModel.hintsLeft) left"
    }

    private var swapLabel: String {
        "Swap \u{00B7} \(viewModel.discardsLeft) left"
    }

    private var boostLabel: String {
        "+30s \u{00B7} \(viewModel.timeBoostsLeft) left"
    }

    private func scoreColumn(name: String, score: Int, active: Bool) -> some View {        VStack(spacing: 2) {
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

/// Board in its own pannable container with pinch / double-tap zoom.
struct ZoomableBoardView: View {
    @ObservedObject var viewModel: GameViewModel
    let cellSize: CGFloat
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        let zCell = cellSize * zoomScale
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            BoardView(viewModel: viewModel, cellSize: zCell)
                .frame(width: gridWidth(zCell), height: gridHeight(zCell))
        }
        .frame(height: 400)
        .gesture(
            MagnificationGesture()
                .onChanged { zoomScale = min(2.5, max(1.0, $0)) }
                .onEnded { _ in if zoomScale < 1.15 { zoomScale = 1.0 } }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.25)) {
                zoomScale = zoomScale > 1.0 ? 1.0 : 1.8
            }
        }
    }

    private func gridWidth(_ c: CGFloat) -> CGFloat {
        CGFloat(viewModel.puzzle.cols) * (c + 3) - 3
    }

    private func gridHeight(_ c: CGFloat) -> CGFloat {
        CGFloat(viewModel.puzzle.rows) * (c + 3) - 3
    }
}

struct BoardView: View {
    @ObservedObject var viewModel: GameViewModel
    let cellSize: CGFloat

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellSize), spacing: 3), count: viewModel.puzzle.cols)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(0..<viewModel.puzzle.cells.count, id: \.self) { i in
                BoardCellView(viewModel: viewModel, index: i, cellSize: cellSize)
            }
        }
    }
}

struct BoardCellView: View {
    @ObservedObject var viewModel: GameViewModel
    let index: Int
    let cellSize: CGFloat

    var body: some View {
        let cell = viewModel.puzzle.cells[index]
        Group {
            switch cell.k {
            case "x":
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
            case "c":
                Button {
                    viewModel.popup = PopupMessage(title: "Clue", text: viewModel.clueText(index))
                } label: {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [Color.yellow.opacity(0.55),
                                         Color.orange.opacity(0.45)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        if viewModel.pictureCluesEnabled,
                           let symbol = viewModel.pictureSymbolForClue(index) {
                            // Picture clue (Kryss-style): show the symbol big.
                            VStack(spacing: 0) {
                                Text(cell.ca != nil ? "\u{2192}" : "\u{2193}")
                                    .font(.system(size: cellSize * 0.22, weight: .bold))
                                Image(systemName: symbol)
                                    .font(.system(size: cellSize * 0.36))
                                    .foregroundColor(.primary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(2)
                        } else {
                            VStack(spacing: 0) {
                                Text(cell.ca != nil ? "\u{2192}" : "\u{2193}")
                                    .font(.system(size: cellSize * 0.28, weight: .bold))
                                Text(shortClue(cell))
                                    .font(.system(size: cellSize * 0.16))
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clue: \(viewModel.clueText(index))")
                .accessibilityHint("Opens the full clue")
            default:
                Button {
                    if let tileID = viewModel.selectedTileID, viewModel.isHumanTurn {
                        viewModel.attemptPlace(tileID: tileID, cell: index)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(cellFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(cellBorderColor, lineWidth: cellBorderWidth)
                            )
                        if viewModel.dropTarget == index {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(style: StrokeStyle(lineWidth: 3, dash: [6]))
                                .foregroundColor(.green)
                        }
                        if let letter = viewModel.filled[index] {
                            Text(letter)
                                .font(.system(size: cellSize * 0.5, weight: .black))
                                .foregroundColor(.white)
                                .shadow(radius: 1)
                        } else if viewModel.selectedTileID != nil && viewModel.isHumanTurn {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if viewModel.turnBlueCells.contains(index) {
                            Text("\u{00D7}2")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(7)
                                .padding(3)
                                .shadow(radius: 1)
                        } else if viewModel.turnCells.contains(index) {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 9, height: 9)
                                .padding(4)
                                .shadow(radius: 1)
                        }
                    }
                    .onDrop(of: [UTType.text],
                            delegate: TileDropDelegate(cell: index, viewModel: viewModel))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isHumanTurn)
                .accessibilityLabel(cellAccessibilityLabel)
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    /// VoiceOver label for a letter cell: picture clues and tiny board
    /// text are hard to see (a recurring Kryss complaint), so every cell
    /// states plainly what it holds.
    private var cellAccessibilityLabel: String {
        if let letter = viewModel.filled[index] { return "Letter \(letter)" }
        if viewModel.isBonus(index) {
            return "Empty bonus square — a correct letter here doubles your turn score"
        }
        return "Empty square"
    }

    private func shortClue(_ cell: PuzzleCell) -> String {
        let text = cell.ca ?? cell.cd ?? ""
        return String(text.prefix(24))
    }

    private var cellFill: AnyShapeStyle {
        if viewModel.filled[index] != nil {
            AnyShapeStyle(Theme.playerGradient(viewModel.filledBy[index]))
        } else if viewModel.isBonus(index) {
            AnyShapeStyle(Theme.bonusGradient)
        } else {
            AnyShapeStyle(Color(.systemBackground))
        }
    }

    private var cellBorderColor: Color {
        if viewModel.filled[index] != nil { return .clear }
        return viewModel.isBonus(index) ? .blue : Color(.systemGray4)
    }

    private var cellBorderWidth: CGFloat {
        if viewModel.filled[index] != nil { return 0 }
        return viewModel.isBonus(index) ? 2 : 1
    }
}

struct RackView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.rack) { tile in
                TileView(
                    tile: tile,
                    selected: viewModel.selectedTileID == tile.id,
                    shaking: viewModel.shakeTileID == tile.id,
                    swapPicked: viewModel.swapPicked.contains(tile.id)
                )
                .onTapGesture {
                    guard viewModel.isHumanTurn, !tile.used else { return }
                    if viewModel.swapPicking {
                        viewModel.toggleSwapPick(tile.id)
                    } else if viewModel.selectedTileID == tile.id {
                        viewModel.selectedTileID = nil
                    } else {
                        viewModel.selectedTileID = tile.id
                    }
                }
                .opacity(tile.used ? 0.25 : 1.0)
                .accessibilityLabel(tile.used
                    ? "Tile \(tile.letter), played"
                    : "Tile \(tile.letter)\(viewModel.selectedTileID == tile.id ? ", selected" : "")")
            }
        }
        .padding(.vertical, 6)
    }
}

struct TileView: View {
    let tile: Tile
    let selected: Bool
    let shaking: Bool
    var swapPicked: Bool = false

    var body: some View {
        Text(tile.letter)
            .font(.system(size: 26, weight: .bold))
            .frame(width: 52, height: 52)
            .background(tileFace)
            .foregroundColor(selected ? .white : .primary)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(shaking ? Color.red : (swapPicked ? Color.blue : Color.clear), lineWidth: 3)
            )
            .scaleEffect(selected ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: selected)
            .onDrag {
                NSItemProvider(object: tile.id.uuidString as NSString)
            } preview: {
                Text(tile.letter)
                    .font(.system(size: 30, weight: .black))
                    .frame(width: 56, height: 56)
                    .background(Theme.tileSelectedGradient)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
    }

    private var tileFace: some View {
        Group {
            if selected {
                Theme.tileSelectedGradient
            } else {
                LinearGradient(colors: [.white, Color(.systemGray5)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// Stand-in ad screen shown when the AdMob SDK is not linked.
/// Real AdMob ads replace this automatically once the SDK is added.
struct MockAdView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("SIMULATED AD")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                Text(title)
                    .font(.title2)
                    .foregroundColor(.white)
                Text("Link the Google Mobile Ads SDK in Xcode\nto serve real ads here.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
            }
            .padding()
        }
    }
}

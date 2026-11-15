import Foundation

// MARK: - Runtime puzzle generation
//
// S.W.I.S.H generates a brand-new arrowword puzzle for every game, the same
// way the genre leaders do: a word/clue database plus a layout algorithm that
// assembles a fresh Scandinavian-style grid on the spot. All words and clues
// are original content written for this game (see tools/gen_puzzles.py).

struct WordEntry: Codable {
    var w: String   // word
    var c: String   // clue
}

private struct PlacedWord {
    var word: String
    var clue: String
    var r: Int
    var c: Int
    var across: Bool
}

final class PuzzleGenerator {
    static let shared = PuzzleGenerator()
    private init() {}

    private(set) var words: [WordEntry] = []
    var hasWords: Bool { !words.isEmpty }

    static let titles = [
        "Warm-Up", "First Serve", "Rally Time", "Smash Hit",
        "Net Play", "Top Spin", "Match Point", "Grand Slam",
        "Fast Break", "Full Court", "Overtime", "Championship"
    ]

    /// Element names clued by their chemical symbols, for Elements mode.
    /// The full periodic table: every word is an element name, every clue
    /// is its symbol (e.g. HELIUM / "He").
    static let elementEntries: [WordEntry] = [
        WordEntry(w: "HYDROGEN", c: "H"), WordEntry(w: "HELIUM", c: "He"),
        WordEntry(w: "LITHIUM", c: "Li"), WordEntry(w: "BERYLLIUM", c: "Be"),
        WordEntry(w: "BORON", c: "B"), WordEntry(w: "CARBON", c: "C"),
        WordEntry(w: "NITROGEN", c: "N"), WordEntry(w: "OXYGEN", c: "O"),
        WordEntry(w: "FLUORINE", c: "F"), WordEntry(w: "NEON", c: "Ne"),
        WordEntry(w: "SODIUM", c: "Na"), WordEntry(w: "MAGNESIUM", c: "Mg"),
        WordEntry(w: "ALUMINUM", c: "Al"), WordEntry(w: "SILICON", c: "Si"),
        WordEntry(w: "PHOSPHORUS", c: "P"), WordEntry(w: "SULFUR", c: "S"),
        WordEntry(w: "CHLORINE", c: "Cl"), WordEntry(w: "ARGON", c: "Ar"),
        WordEntry(w: "POTASSIUM", c: "K"), WordEntry(w: "CALCIUM", c: "Ca"),
        WordEntry(w: "SCANDIUM", c: "Sc"), WordEntry(w: "TITANIUM", c: "Ti"),
        WordEntry(w: "VANADIUM", c: "V"), WordEntry(w: "CHROMIUM", c: "Cr"),
        WordEntry(w: "MANGANESE", c: "Mn"), WordEntry(w: "IRON", c: "Fe"),
        WordEntry(w: "COBALT", c: "Co"), WordEntry(w: "NICKEL", c: "Ni"),
        WordEntry(w: "COPPER", c: "Cu"), WordEntry(w: "ZINC", c: "Zn"),
        WordEntry(w: "GALLIUM", c: "Ga"), WordEntry(w: "GERMANIUM", c: "Ge"),
        WordEntry(w: "ARSENIC", c: "As"), WordEntry(w: "SELENIUM", c: "Se"),
        WordEntry(w: "BROMINE", c: "Br"), WordEntry(w: "KRYPTON", c: "Kr"),
        WordEntry(w: "RUBIDIUM", c: "Rb"), WordEntry(w: "STRONTIUM", c: "Sr"),
        WordEntry(w: "YTTRIUM", c: "Y"), WordEntry(w: "ZIRCONIUM", c: "Zr"),
        WordEntry(w: "NIOBIUM", c: "Nb"), WordEntry(w: "MOLYBDENUM", c: "Mo"),
        WordEntry(w: "TECHNETIUM", c: "Tc"), WordEntry(w: "RUTHENIUM", c: "Ru"),
        WordEntry(w: "RHODIUM", c: "Rh"), WordEntry(w: "PALLADIUM", c: "Pd"),
        WordEntry(w: "SILVER", c: "Ag"), WordEntry(w: "CADMIUM", c: "Cd"),
        WordEntry(w: "INDIUM", c: "In"), WordEntry(w: "TIN", c: "Sn"),
        WordEntry(w: "ANTIMONY", c: "Sb"), WordEntry(w: "TELLURIUM", c: "Te"),
        WordEntry(w: "IODINE", c: "I"), WordEntry(w: "XENON", c: "Xe"),
        WordEntry(w: "CESIUM", c: "Cs"), WordEntry(w: "BARIUM", c: "Ba"),
        WordEntry(w: "LANTHANUM", c: "La"), WordEntry(w: "CERIUM", c: "Ce"),
        WordEntry(w: "PRASEODYMIUM", c: "Pr"), WordEntry(w: "NEODYMIUM", c: "Nd"),
        WordEntry(w: "PROMETHIUM", c: "Pm"), WordEntry(w: "SAMARIUM", c: "Sm"),
        WordEntry(w: "EUROPIUM", c: "Eu"), WordEntry(w: "GADOLINIUM", c: "Gd"),
        WordEntry(w: "TERBIUM", c: "Tb"), WordEntry(w: "DYSPROSIUM", c: "Dy"),
        WordEntry(w: "HOLMIUM", c: "Ho"), WordEntry(w: "ERBIUM", c: "Er"),
        WordEntry(w: "THULIUM", c: "Tm"), WordEntry(w: "YTTERBIUM", c: "Yb"),
        WordEntry(w: "LUTETIUM", c: "Lu"), WordEntry(w: "HAFNIUM", c: "Hf"),
        WordEntry(w: "TANTALUM", c: "Ta"), WordEntry(w: "TUNGSTEN", c: "W"),
        WordEntry(w: "RHENIUM", c: "Re"), WordEntry(w: "OSMIUM", c: "Os"),
        WordEntry(w: "IRIDIUM", c: "Ir"), WordEntry(w: "PLATINUM", c: "Pt"),
        WordEntry(w: "GOLD", c: "Au"), WordEntry(w: "MERCURY", c: "Hg"),
        WordEntry(w: "THALLIUM", c: "Tl"), WordEntry(w: "LEAD", c: "Pb"),
        WordEntry(w: "BISMUTH", c: "Bi"), WordEntry(w: "POLONIUM", c: "Po"),
        WordEntry(w: "ASTATINE", c: "At"), WordEntry(w: "RADON", c: "Rn"),
        WordEntry(w: "FRANCIUM", c: "Fr"), WordEntry(w: "RADIUM", c: "Ra"),
        WordEntry(w: "ACTINIUM", c: "Ac"), WordEntry(w: "THORIUM", c: "Th"),
        WordEntry(w: "PROTACTINIUM", c: "Pa"), WordEntry(w: "URANIUM", c: "U"),
        WordEntry(w: "NEPTUNIUM", c: "Np"), WordEntry(w: "PLUTONIUM", c: "Pu"),
        WordEntry(w: "AMERICIUM", c: "Am"), WordEntry(w: "CURIUM", c: "Cm"),
        WordEntry(w: "BERKELIUM", c: "Bk"), WordEntry(w: "CALIFORNIUM", c: "Cf"),
        WordEntry(w: "EINSTEINIUM", c: "Es"), WordEntry(w: "FERMIUM", c: "Fm"),
        WordEntry(w: "MENDELEVIUM", c: "Md"), WordEntry(w: "NOBELIUM", c: "No"),
        WordEntry(w: "LAWRENCIUM", c: "Lr"), WordEntry(w: "RUTHERFORDIUM", c: "Rf"),
        WordEntry(w: "DUBNIUM", c: "Db"), WordEntry(w: "SEABORGIUM", c: "Sg"),
        WordEntry(w: "BOHRIUM", c: "Bh"), WordEntry(w: "HASSIUM", c: "Hs"),
        WordEntry(w: "MEITNERIUM", c: "Mt"), WordEntry(w: "DARMSTADTIUM", c: "Ds"),
        WordEntry(w: "ROENTGENIUM", c: "Rg"), WordEntry(w: "COPERNICIUM", c: "Cn"),
        WordEntry(w: "NIHONIUM", c: "Nh"), WordEntry(w: "FLEROVIUM", c: "Fl"),
        WordEntry(w: "MOSCOVIUM", c: "Mc"), WordEntry(w: "LIVERMORIUM", c: "Lv"),
        WordEntry(w: "TENNESSINE", c: "Ts"), WordEntry(w: "OGANESSON", c: "Og"),
    ]

    /// Loads the bundled word/clue database. Call once at app launch.
    func loadWords() {
        guard words.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WordEntry].self, from: data)
        else { return }
        words = list
    }

    /// Builds a fresh puzzle on a background queue, then delivers it on main.
    /// Pass a custom word list (e.g. elementEntries) to build from it instead
    /// of the bundled database.
    func generate(title: String? = nil, restarts: Int = 40,
                  using wordList: [WordEntry]? = nil,
                  completion: @escaping (Puzzle) -> Void) {
        let t = title ?? (Self.titles.randomElement() ?? "Puzzle")
        let list = wordList ?? words
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, !list.isEmpty else { return }
            let puzzle = self.build(title: t, restarts: restarts, words: list)
            DispatchQueue.main.async { completion(puzzle) }
        }
    }

    // MARK: - Layout algorithm

    private func build(title: String, restarts: Int, words: [WordEntry]) -> Puzzle {
        let cols = 8, rows = 12
        var bestGrid: [[String?]]? = nil
        var bestPlaced: [PlacedWord] = []
        var bestScore = (-1, -1)
        for _ in 0..<restarts {
            let (grid, placed) = buildOnce(cols: cols, rows: rows, words: words)
            let letters = grid.flatMap { $0 }.filter { $0 != nil && $0 != "#" }.count
            let score = (placed.count, letters)
            if score > bestScore {
                bestScore = score
                bestGrid = grid
                bestPlaced = placed
            }
        }
        return finalize(grid: bestGrid!, placed: bestPlaced,
                        title: title, cols: cols, rows: rows)
    }

    private func buildOnce(cols: Int, rows: Int, words: [WordEntry]) -> ([[String?]], [PlacedWord]) {
        var grid: [[String?]] = Array(repeating: Array(repeating: nil, count: cols),
                                     count: rows)
        var placed: [PlacedWord] = []
        var pool = words.shuffled()

        // Seed: longest placeable word, across the middle of the board,
        // falling back to down the middle, then to shorter words.
        // (Long words can't always fit across an 8-column grid.)
        let candidates = pool.sorted { $0.w.count > $1.w.count }
        for cand in candidates {
            let r0 = rows / 2
            let c0 = max(1, (cols - cand.w.count) / 2)
            if canPlace(grid, cand.w, r0, c0, true, cols, rows) != nil {
                pool.removeAll { $0.w == cand.w }
                doPlace(&grid, cand.w, r0, c0, true)
                placed.append(PlacedWord(word: cand.w, clue: cand.c,
                                         r: r0, c: c0, across: true))
                break
            }
            let rd = max(1, (rows - cand.w.count) / 2)
            let cd = cols / 2
            if canPlace(grid, cand.w, rd, cd, false, cols, rows) != nil {
                pool.removeAll { $0.w == cand.w }
                doPlace(&grid, cand.w, rd, cd, false)
                placed.append(PlacedWord(word: cand.w, clue: cand.c,
                                         r: rd, c: cd, across: false))
                break
            }
        }

        // Greedy passes: place each word at its best crossing point.
        for _ in 0..<6 {
            pool.shuffle()
            var progress = false
            for cand in pool {
                var best: (crossings: Int, r: Int, c: Int, across: Bool)? = nil
                for across in [true, false] {
                    for p in placed where p.across != across {
                        let pchars = Array(p.word)
                        let wchars = Array(cand.w)
                        for (j, pch) in pchars.enumerated() {
                            let jr = p.across ? p.r : p.r + j
                            let jc = p.across ? p.c + j : p.c
                            for (i, ch) in wchars.enumerated() where ch == pch {
                                let rr = jr - (across ? 0 : i)
                                let cc = jc - (across ? i : 0)
                                if let x = canPlace(grid, cand.w, rr, cc, across,
                                                    cols, rows), x >= 1,
                                   best == nil || x > best!.crossings {
                                    best = (x, rr, cc, across)
                                }
                            }
                        }
                    }
                }
                if let b = best {
                    doPlace(&grid, cand.w, b.r, b.c, b.across)
                    placed.append(PlacedWord(word: cand.w, clue: cand.c,
                                             r: b.r, c: b.c, across: b.across))
                    pool.removeAll { $0.w == cand.w }
                    progress = true
                }
            }
            if !progress { break }
        }
        return (grid, placed)
    }

    /// Returns the crossing count if `word` fits at (r, c), else nil.
    /// "#" marks clue cells: letters may never be placed on them.
    private func canPlace(_ grid: [[String?]], _ word: String,
                          _ r: Int, _ c: Int, _ across: Bool,
                          _ cols: Int, _ rows: Int) -> Int? {
        let dr = across ? 0 : 1
        let dc = across ? 1 : 0
        if across && c == 0 { return nil }
        if !across && r == 0 { return nil }
        let chars = Array(word)
        var cells: [(Int, Int)] = []
        var crossings = 0
        for (i, ch) in chars.enumerated() {
            let rr = r + dr * i, cc = c + dc * i
            guard rr >= 0 && rr < rows && cc >= 0 && cc < cols else { return nil }
            let g = grid[rr][cc]
            if g == "#" { return nil }
            if let g = g, g != String(ch) { return nil }
            if g == String(ch) { crossings += 1 }
            cells.append((rr, cc))
        }
        // The clue cell (left of / above the word start) must hold no letter.
        let qr = across ? r : r - 1
        let qc = across ? c - 1 : c
        let q = grid[qr][qc]
        if q != nil && q != "#" { return nil }
        // Fresh cells must not touch other letters sideways (no strays).
        for (rr, cc) in cells {
            if grid[rr][cc] != nil { continue }
            if across {
                for nr in [rr - 1, rr + 1] where nr >= 0 && nr < rows {
                    let n = grid[nr][cc]
                    if n != nil && n != "#" { return nil }
                }
            } else {
                for nc in [cc - 1, cc + 1] where nc >= 0 && nc < cols {
                    let n = grid[rr][nc]
                    if n != nil && n != "#" { return nil }
                }
            }
        }
        // Cells before the start and after the end must hold no letter.
        let br = r - dr, bc = c - dc
        if br >= 0 && br < rows && bc >= 0 && bc < cols {
            let b = grid[br][bc]
            if b != nil && b != "#" { return nil }
        }
        let er = r + dr * chars.count, ec = c + dc * chars.count
        if er >= 0 && er < rows && ec >= 0 && ec < cols {
            let e = grid[er][ec]
            if e != nil && e != "#" { return nil }
        }
        return crossings
    }

    private func doPlace(_ grid: inout [[String?]], _ word: String,
                        _ r: Int, _ c: Int, _ across: Bool) {
        for (i, ch) in Array(word).enumerated() {
            let rr = r + (across ? 0 : i)
            let cc = c + (across ? i : 0)
            grid[rr][cc] = String(ch)
        }
        let qr = across ? r : r - 1
        let qc = across ? c - 1 : c
        grid[qr][qc] = "#"
    }

    private func finalize(grid: [[String?]], placed: [PlacedWord],
                          title: String, cols: Int, rows: Int) -> Puzzle {
        var clueA: [Int: String] = [:]
        var clueD: [Int: String] = [:]
        for p in placed {
            let qi = p.across ? p.r * cols + (p.c - 1) : (p.r - 1) * cols + p.c
            if p.across { clueA[qi] = p.clue } else { clueD[qi] = p.clue }
        }
        var cells: [PuzzleCell] = []
        var letterIdx: [Int] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let i = r * cols + c
                let g = grid[r][c]
                if g == "#" {
                    cells.append(PuzzleCell(k: "c", s: nil,
                                            ca: clueA[i], cd: clueD[i], b: nil))
                } else if let ch = g {
                    cells.append(PuzzleCell(k: "l", s: ch,
                                            ca: nil, cd: nil, b: nil))
                    letterIdx.append(i)
                } else {
                    cells.append(PuzzleCell(k: "x", s: nil,
                                            ca: nil, cd: nil, b: nil))
                }
            }
        }
        // 3 blue bonus squares on random letter cells.
        for i in letterIdx.shuffled().prefix(3) {
            cells[i].b = true
        }
        let words = placed.map {
            PuzzleWord(a: $0.word, r: $0.r, c: $0.c,
                       d: $0.across ? "across" : "down")
        }
        return Puzzle(id: UUID().uuidString, title: title,
                      cols: cols, rows: rows, cells: cells, words: words)
    }
}

// MARK: - Prefetch pool
//
// Keeps one fresh puzzle buffered so starting a game feels instant:
// generation runs in the background while the user is on the menu or
// mid-game, and the next game grabs the buffered puzzle.

final class PuzzlePool {
    static let shared = PuzzlePool()
    private init() {}

    private var ready: [Puzzle] = []
    private var generating = false

    func warmup() { ensure() }

    /// Takes a buffered fresh puzzle if one is ready, else nil.
    func take() -> Puzzle? {
        guard !ready.isEmpty else { return nil }
        let p = ready.removeFirst()
        ensure()
        return p
    }

    private func ensure() {
        guard !generating, PuzzleGenerator.shared.hasWords else { return }
        generating = true
        PuzzleGenerator.shared.generate { [weak self] puzzle in
            guard let self = self else { return }
            self.ready.append(puzzle)
            self.generating = false
        }
    }
}

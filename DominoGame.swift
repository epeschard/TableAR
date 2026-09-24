import Foundation
import Combine

struct DominoFace: Hashable, Identifiable {
    let a: Int
    let b: Int

    var id: String { "\(min(a, b))-\(max(a, b))" }

    var isDouble: Bool { a == b }
    var pipTotal: Int { a + b }

    func contains(_ value: Int) -> Bool { a == value || b == value }

    func other(than value: Int) -> Int? {
        if a == value { return b }
        if b == value { return a }
        return nil
    }

    func exposedValue(matching end: Int) -> Int? {
        other(than: end)
    }

    static func doubleSixSet() -> [DominoFace] {
        var tiles: [DominoFace] = []
        for low in 0...6 {
            for high in low...6 {
                tiles.append(DominoFace(a: low, b: high))
            }
        }
        return tiles
    }
}

enum DominoPlayer: Int, CaseIterable {
    case human = 0
    case ai = 1

    var label: String {
        switch self {
        case .human: return "You"
        case .ai: return "Opponent"
        }
    }
}

enum DominoPhase: Equatable {
    case idle
    case waitingToDeal
    case playing
    case finished
}

struct PlayedDomino: Identifiable, Equatable {
    let id: String
    let face: DominoFace
    let inwardValue: Int
    let exposedValue: Int
    let isCrosswise: Bool
    let growsLeft: Bool
}

struct OpenEnd: Equatable {
    enum Side: String {
        case left
        case right
    }

    var side: Side
    var value: Int
}

struct DominoTurnResult {
    var message: String
    var didPlay: Bool
    var gameOver: Bool
}

final class DominoGame: ObservableObject {
    @Published var rules: DominoRules = .draw
    @Published var phase: DominoPhase = .idle
    @Published var currentPlayer: DominoPlayer = .human
    @Published var hands: [DominoPlayer: [DominoFace]] = [.human: [], .ai: []]
    @Published var boneyard: [DominoFace] = []
    @Published var chain: [PlayedDomino] = []
    @Published var openEnds: [OpenEnd] = []
    @Published var status: String = "Choose Draw or Block, then deal."
    @Published var winner: DominoPlayer?
    @Published var humanScoreAgainst: Int = 0
    @Published var lastPassCount: Int = 0

    var humanHand: [DominoFace] { hands[.human] ?? [] }
    var aiHand: [DominoFace] { hands[.ai] ?? [] }

    func resetBoardKeepingRules() {
        phase = .waitingToDeal
        currentPlayer = .human
        hands = [.human: [], .ai: []]
        boneyard = []
        chain = []
        openEnds = []
        winner = nil
        humanScoreAgainst = 0
        lastPassCount = 0
        status = "Tap Deal to start a \(rules.title) game on the table."
    }

    func deal() {
        var deck = DominoFace.doubleSixSet().shuffled()
        let human = Array(deck.prefix(7))
        deck.removeFirst(7)
        let ai = Array(deck.prefix(7))
        deck.removeFirst(7)

        hands = [.human: human, .ai: ai]
        boneyard = deck
        chain = []
        openEnds = []
        winner = nil
        humanScoreAgainst = 0
        lastPassCount = 0
        phase = .playing

        if let start = openingPlayerAndTile() {
            currentPlayer = start.player
            status = "\(start.player.label) starts with \(label(start.tile))."
        } else {
            currentPlayer = .human
            status = "Your turn — play any tile to start the chain."
        }
    }

    private func openingPlayerAndTile() -> (player: DominoPlayer, tile: DominoFace)? {
        func bestDouble(in tiles: [DominoFace]) -> DominoFace? {
            tiles.filter(\.isDouble).max(by: { $0.a < $1.a })
        }
        func bestTile(in tiles: [DominoFace]) -> DominoFace? {
            tiles.max(by: { lhs, rhs in
                if lhs.pipTotal != rhs.pipTotal { return lhs.pipTotal < rhs.pipTotal }
                return max(lhs.a, lhs.b) < max(rhs.a, rhs.b)
            })
        }

        let humanDouble = bestDouble(in: humanHand)
        let aiDouble = bestDouble(in: aiHand)
        switch (humanDouble, aiDouble) {
        case let (h?, a?):
            return h.a >= a.a ? (.human, h) : (.ai, a)
        case let (h?, nil):
            return (.human, h)
        case let (nil, a?):
            return (.ai, a)
        default:
            break
        }

        if let h = bestTile(in: humanHand), let a = bestTile(in: aiHand) {
            if h.pipTotal == a.pipTotal {
                return max(h.a, h.b) >= max(a.a, a.b) ? (.human, h) : (.ai, a)
            }
            return h.pipTotal > a.pipTotal ? (.human, h) : (.ai, a)
        }
        return nil
    }

    func suggestedOpeningTile(for player: DominoPlayer) -> DominoFace? {
        openingPlayerAndTile().flatMap { $0.player == player ? $0.tile : nil }
    }

    func legalPlays(for tile: DominoFace) -> [OpenEnd] {
        if chain.isEmpty { return [OpenEnd(side: .right, value: -1)] }
        return openEnds.filter { tile.contains($0.value) }
    }

    func canPlay(_ tile: DominoFace) -> Bool {
        !legalPlays(for: tile).isEmpty
    }

    func playableTiles(for player: DominoPlayer) -> [DominoFace] {
        (hands[player] ?? []).filter { canPlay($0) }
    }

    func mustDrawOrPass(player: DominoPlayer) -> Bool {
        playableTiles(for: player).isEmpty
    }

    @discardableResult
    func play(tile: DominoFace, on end: OpenEnd?, player: DominoPlayer) -> DominoTurnResult {
        guard phase == .playing, currentPlayer == player else {
            return DominoTurnResult(message: "Not your turn.", didPlay: false, gameOver: false)
        }
        guard var hand = hands[player], let idx = hand.firstIndex(of: tile) else {
            return DominoTurnResult(message: "That tile is not in hand.", didPlay: false, gameOver: false)
        }

        if chain.isEmpty {
            hand.remove(at: idx)
            hands[player] = hand
            let played = PlayedDomino(
                id: tile.id + "-0",
                face: tile,
                inwardValue: tile.a,
                exposedValue: tile.b,
                isCrosswise: tile.isDouble,
                growsLeft: false
            )
            chain = [played]
            if tile.isDouble {
                openEnds = [
                    OpenEnd(side: .left, value: tile.a),
                    OpenEnd(side: .right, value: tile.a)
                ]
            } else {
                openEnds = [
                    OpenEnd(side: .left, value: tile.a),
                    OpenEnd(side: .right, value: tile.b)
                ]
            }
            lastPassCount = 0
            return finishPlay(player: player, tile: tile)
        }

        guard let chosen = resolvedEnd(for: tile, preferred: end) else {
            return DominoTurnResult(message: "No matching end for \(label(tile)).", didPlay: false, gameOver: false)
        }

        hand.remove(at: idx)
        hands[player] = hand

        let exposed = tile.isDouble ? chosen.value : (tile.exposedValue(matching: chosen.value) ?? chosen.value)
        let played = PlayedDomino(
            id: tile.id + "-\(chain.count)",
            face: tile,
            inwardValue: chosen.value,
            exposedValue: exposed,
            isCrosswise: tile.isDouble,
            growsLeft: chosen.side == .left
        )

        if chosen.side == .left {
            chain.insert(played, at: 0)
        } else {
            chain.append(played)
        }

        if let i = openEnds.firstIndex(where: { $0.side == chosen.side }) {
            openEnds[i].value = exposed
        }
        lastPassCount = 0
        return finishPlay(player: player, tile: tile)
    }

    private func resolvedEnd(for tile: DominoFace, preferred: OpenEnd?) -> OpenEnd? {
        let options = legalPlays(for: tile)
        if let preferred, options.contains(preferred) { return preferred }
        return options.first
    }

    private func finishPlay(player: DominoPlayer, tile: DominoFace) -> DominoTurnResult {
        if (hands[player] ?? []).isEmpty {
            phase = .finished
            winner = player
            let opponent: DominoPlayer = player == .human ? .ai : .human
            let leftover = (hands[opponent] ?? []).reduce(0) { $0 + $1.pipTotal }
            humanScoreAgainst = player == .human ? leftover : -leftover
            status = "\(player.label) went out. Pips in opponent hand: \(leftover)."
            return DominoTurnResult(message: status, didPlay: true, gameOver: true)
        }

        currentPlayer = player == .human ? .ai : .human
        status = "Played \(label(tile)). \(currentPlayer.label) to move. Ends \(endSummary())."
        return DominoTurnResult(message: status, didPlay: true, gameOver: false)
    }

    func draw(player: DominoPlayer) -> DominoFace? {
        guard phase == .playing, currentPlayer == player else { return nil }
        guard rules == .draw else { return nil }
        guard playableTiles(for: player).isEmpty else { return nil }
        guard !boneyard.isEmpty else { return nil }
        let tile = boneyard.removeFirst()
        hands[player, default: []].append(tile)
        status = "\(player.label) drew a tile. Boneyard: \(boneyard.count)."
        return tile
    }

    func drawUntilPlayableOrEmpty(player: DominoPlayer) -> [DominoFace] {
        var drawn: [DominoFace] = []
        while playableTiles(for: player).isEmpty, !boneyard.isEmpty, rules == .draw {
            if let tile = draw(player: player) {
                drawn.append(tile)
            } else {
                break
            }
        }
        return drawn
    }

    @discardableResult
    func pass(player: DominoPlayer) -> DominoTurnResult {
        guard phase == .playing, currentPlayer == player else {
            return DominoTurnResult(message: "Not your turn.", didPlay: false, gameOver: false)
        }
        guard playableTiles(for: player).isEmpty else {
            return DominoTurnResult(message: "You still have a legal play.", didPlay: false, gameOver: false)
        }
        if rules == .draw && !boneyard.isEmpty {
            return DominoTurnResult(message: "Draw from the boneyard first.", didPlay: false, gameOver: false)
        }

        lastPassCount += 1
        if lastPassCount >= 2 {
            return endBlockedGame()
        }

        currentPlayer = player == .human ? .ai : .human
        status = "\(player.label) passes. \(currentPlayer.label) to move. Ends \(endSummary())."
        return DominoTurnResult(message: status, didPlay: false, gameOver: false)
    }

    private func endBlockedGame() -> DominoTurnResult {
        phase = .finished
        let humanPips = humanHand.reduce(0) { $0 + $1.pipTotal }
        let aiPips = aiHand.reduce(0) { $0 + $1.pipTotal }
        if humanPips < aiPips {
            winner = .human
            humanScoreAgainst = aiPips
        } else if aiPips < humanPips {
            winner = .ai
            humanScoreAgainst = -humanPips
        } else {
            winner = nil
            humanScoreAgainst = 0
        }
        let who = winner?.label ?? "Nobody"
        status = "Blocked. You \(humanPips) pips, opponent \(aiPips). \(who) wins."
        return DominoTurnResult(message: status, didPlay: false, gameOver: true)
    }

    func chooseAIPlay() -> (tile: DominoFace, end: OpenEnd)? {
        let tiles = playableTiles(for: .ai)
        guard !tiles.isEmpty else { return nil }
        let sorted = tiles.sorted { lhs, rhs in
            if lhs.isDouble != rhs.isDouble { return lhs.isDouble && !rhs.isDouble }
            return lhs.pipTotal > rhs.pipTotal
        }
        guard let tile = sorted.first, let end = legalPlays(for: tile).first else { return nil }
        return (tile, end)
    }

    func endSummary() -> String {
        if chain.isEmpty { return "empty chain" }
        let values = openEnds.map { "\($0.side.rawValue) \($0.value)" }
        return values.joined(separator: " · ")
    }

    func label(_ tile: DominoFace) -> String {
        "[\(tile.a)|\(tile.b)]"
    }
}

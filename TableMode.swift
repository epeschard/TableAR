import Foundation

enum TableMode: String, CaseIterable, Identifiable {
    case cards
    case dominoes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .dominoes: return "Dominoes"
        }
    }

    var systemImage: String {
        switch self {
        case .cards: return "rectangle.on.rectangle"
        case .dominoes: return "circle.grid.3x3.fill"
        }
    }
}

enum DominoRules: String, CaseIterable, Identifiable {
    case draw
    case block

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draw: return "Draw"
        case .block: return "Block"
        }
    }

    var detail: String {
        switch self {
        case .draw:
            return "If you cannot play, draw from the boneyard until you can, or it is empty."
        case .block:
            return "If you cannot play, pass. No drawing. Game ends when both players pass."
        }
    }
}

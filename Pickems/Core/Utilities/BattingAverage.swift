import Foundation

enum BattingAverage {
    static func rate(wins: Int, losses: Int) -> Double {
        let total = wins + losses
        guard total > 0 else { return 0 }
        return Double(wins) / Double(total)
    }

    static func formatted(wins: Int, losses: Int, precision: Int = 3) -> String {
        String(format: "%.\(precision)f", rate(wins: wins, losses: losses))
    }
}

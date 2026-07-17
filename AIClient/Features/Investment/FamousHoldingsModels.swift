import Foundation

struct FamousHoldingsResponse: Decodable {
    let success: Bool
    let data: FamousHoldings
}

struct FamousHoldings: Decodable {
    let generatedAt: String
    let reportDate: String
    let periodLabel: String
    let disclaimer: String
    let summary: FamousHoldingsSummary
    let managers: [FamousHoldingsManager]
}

struct FamousHoldingsSummary: Decodable {
    let new: Int
    let increased: Int
    let decreased: Int
    let exited: Int
}

struct FamousHoldingsManager: Decodable, Identifiable {
    let key: String
    let cik: String
    let displayName: String
    let institutionName: String
    let reportDate: String
    let filingDate: String
    let positionsCount: Int
    let totalValueUsd: Double
    let summary: FamousHoldingsSummary
    let changesCount: Int
    let changes: [FamousHoldingChange]

    var id: String { key }
}

struct FamousHoldingChange: Decodable, Identifiable {
    let symbol: String?
    let name: String
    let companyLogo: String?
    let action: FamousHoldingAction
    let previousWeightPct: Double
    let weightPct: Double
    let weightChangePct: Double
    let valueUsd: Double

    var id: String { "\(symbol ?? name)-\(action.rawValue)" }
}

enum FamousHoldingAction: String, Decodable {
    case new
    case increased
    case decreased
    case exited

    var title: String {
        switch self {
        case .new: "新建仓"
        case .increased: "增持"
        case .decreased: "减持"
        case .exited: "清仓"
        }
    }
}

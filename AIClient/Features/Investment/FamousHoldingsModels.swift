import Foundation

struct FamousHoldingsResponse: Codable {
    let success: Bool
    let data: FamousHoldings
}

struct FamousHoldings: Codable {
    let generatedAt: String
    let reportDate: String
    let periodLabel: String
    let disclaimer: String
    let summary: FamousHoldingsSummary
    let managers: [FamousHoldingsManager]
}

struct FamousHoldingsSummary: Codable {
    let new: Int
    let increased: Int
    let decreased: Int
    let exited: Int
    let unchanged: Int
}

struct FamousHoldingsManager: Codable, Identifiable {
    let key: String
    let displayName: String
    let institutionName: String
    let reportDate: String
    let filingDate: String
    let accession: String
    let filingUrl: URL?
    let holdingsCount: Int
    let positionsCount: Int
    let totalValueUsd: Double
    let summary: FamousHoldingsSummary
    let analytics: FamousHoldingsAnalytics
    let topPositions: [FamousHoldingPositionSummary]?
    let positions: [FamousHoldingChange]?
    let exitedPositions: [FamousHoldingChange]?

    var id: String { key }

    var reportIdentity: FamousHoldingsReportIdentity {
        FamousHoldingsReportIdentity(managerKey: key, reportDate: reportDate, filingDate: filingDate, accession: accession)
    }

    var hasCompletePositions: Bool {
        (positions?.count ?? 0) == positionsCount && (exitedPositions?.count ?? 0) == summary.exited
    }

    var canCompare: Bool { analytics.previousReportDate != nil }
}

struct FamousHoldingsReportIdentity: Hashable {
    let managerKey: String
    let reportDate: String
    let filingDate: String
    let accession: String

    func covers(_ requested: Self) -> Bool {
        guard managerKey == requested.managerKey else { return false }
        if reportDate != requested.reportDate { return reportDate > requested.reportDate }
        if filingDate != requested.filingDate { return filingDate > requested.filingDate }
        return accession == requested.accession
    }
}

struct FamousHoldingsAnalytics: Codable {
    let previousReportDate: String?
    let previousTotalValueUsd: Double?
    let totalValueChangeUsd: Double
    let totalValueChangePct: Double
}

struct FamousHoldingPositionSummary: Codable, Identifiable {
    let id: String
    let name: String
    let symbol: String?
    let weightPct: Double
    let valueUsd: Double

    init(_ position: FamousHoldingChange) {
        let isExited = position.action == .exited
        id = position.id
        name = position.name
        symbol = position.symbol
        weightPct = isExited ? position.previousWeightPct : position.weightPct
        valueUsd = isExited ? position.previousValueUsd : position.valueUsd
    }
}

struct FamousHoldingChange: Codable, Identifiable {
    let id: String
    let name: String
    let symbol: String?
    let originalName: String
    let cusip: String
    let titleOfClass: String
    let putCall: String?
    let sharesType: String?
    let action: FamousHoldingAction
    let previousWeightPct: Double
    let weightPct: Double
    let weightChangePct: Double
    let valueUsd: Double
    let previousValueUsd: Double
}

enum HoldingDisclosureType: String, CaseIterable, Identifiable {
    case shares = "按股或份额申报"
    case put = "看跌期权"
    case call = "看涨期权"
    case principal = "按本金申报"
    case unknown = "申报类型未识别"

    var id: Self { self }

    init(position: FamousHoldingChange) {
        switch (position.putCall?.uppercased(), position.sharesType?.uppercased()) {
        case ("PUT", _): self = .put
        case ("CALL", _): self = .call
        case (_, "PRN"): self = .principal
        case (_, "SH"): self = .shares
        default: self = .unknown
        }
    }
}

enum FamousHoldingAction: String, Codable {
    case new
    case increased
    case decreased
    case exited
    case unchanged

    var title: String {
        switch self {
        case .new: "新建仓"
        case .increased: "增持"
        case .decreased: "减持"
        case .exited: "清仓"
        case .unchanged: "数量未变"
        }
    }
}

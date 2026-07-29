import Foundation

struct LearningCatalog: Decodable, Equatable {
    let source: String
    let fetchedAt: Date
    let sections: [LearningSection]

    enum CodingKeys: String, CodingKey {
        case source, sections
        case fetchedAt = "fetched_at"
    }

    var topicCount: Int { sections.reduce(0) { $0 + $1.topics.count } }
}

struct LearningSection: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let topics: [LearningTopic]
}

struct LearningTopic: Decodable, Identifiable, Hashable {
    let id: String
    let lessonID: String
    let title: String
    let summary: String
    let category: String
    let sourceURLValue: String
    let thumbnailURLValue: String?
    let hasVideo: Bool?
    let detail: LearningDetail?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, category, detail
        case lessonID = "lesson_id"
        case sourceURLValue = "source_url"
        case thumbnailURLValue = "thumbnail_url"
        case hasVideo = "has_video"
    }

    var url: URL { URL(string: sourceURLValue) ?? LearningService.sourceURL }

    func mediaURL(_ value: String?, baseURL: URL = ServerConfiguration.currentURL) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil { return absolute }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }
}

struct LearningDetail: Decodable, Hashable {
    let title: String
    let subtitle: String
    let views: Int
    let viewsText: String
    let updatedAt: String
    let videoURLValue: String?
    let videoPosterURLValue: String?
    let videoDuration: Int?
    let blocks: [LearningBlock]

    enum CodingKeys: String, CodingKey {
        case title, subtitle, views, blocks
        case viewsText = "views_text"
        case updatedAt = "updated_at"
        case videoURLValue = "video_url"
        case videoPosterURLValue = "video_poster_url"
        case videoDuration = "video_duration_seconds"
    }
}

struct LearningBlock: Decodable, Hashable, Identifiable {
    let type: String
    let text: String?
    let level: Int?
    let items: [String]?
    let imageURLValue: String?
    let alt: String?

    enum CodingKeys: String, CodingKey {
        case type, text, level, items, alt
        case imageURLValue = "image_url"
    }

    var id: String {
        [type, text ?? "", imageURLValue ?? "", items?.joined(separator: "|") ?? ""]
            .joined(separator: ":")
    }
}

struct LearningCatalogResponse: Decodable { let data: LearningCatalog }
struct LearningTopicResponse: Decodable { let data: LearningTopic }

struct KnowledgeBook: Identifiable, Hashable {
    let id: String
    let title: String
    let originalTitle: String?
    let author: String
    let summary: String
    let recommendation: String
    let suitableFor: String
    let keyIdeas: [String]

    static let featured: [KnowledgeBook] = [
        KnowledgeBook(
            id: "the-intelligent-investor",
            title: "聪明的投资者",
            originalTitle: "The Intelligent Investor",
            author: "本杰明·格雷厄姆",
            summary: "建立价值投资的基本框架，理解安全边际、市场波动与长期纪律之间的关系。",
            recommendation: "它不负责预测下一次涨跌，而是帮助你形成一套在市场情绪变化时仍能坚持的决策原则。",
            suitableFor: "刚开始建立投资体系，或希望重新审视风险与收益关系的读者。",
            keyIdeas: ["区分投资与投机", "把市场先生当作报价者", "用安全边际保护判断误差"]
        ),
        KnowledgeBook(
            id: "poor-charlies-almanack",
            title: "穷查理宝典",
            originalTitle: "Poor Charlie's Almanack",
            author: "查理·芒格",
            summary: "用跨学科思维模型理解商业、心理偏差与长期复利，训练更清醒的判断力。",
            recommendation: "投资只是它的一个应用场景，真正值得反复阅读的是如何减少愚蠢决定、提高思考质量。",
            suitableFor: "希望拓宽分析视角，并把投资判断连接到商业常识与行为心理的读者。",
            keyIdeas: ["建立多元思维模型", "识别常见心理偏差", "优先避免可预见的错误"]
        ),
        KnowledgeBook(
            id: "the-most-important-thing",
            title: "投资最重要的事",
            originalTitle: "The Most Important Thing",
            author: "霍华德·马克斯",
            summary: "从第二层思维、周期、风险控制和逆向投资出发，解释优秀判断如何形成。",
            recommendation: "文字简洁，但每一章都适合结合真实市场反复复盘，尤其适合在行情热烈时阅读。",
            suitableFor: "已经了解基础概念，希望进一步理解风险、价格与市场共识的读者。",
            keyIdeas: ["练习第二层思维", "风险不等于价格波动", "在周期与共识中保持清醒"]
        ),
        KnowledgeBook(
            id: "berkshire-shareholder-letters",
            title: "巴菲特致股东的信",
            originalTitle: "Berkshire Hathaway Shareholder Letters",
            author: "沃伦·巴菲特",
            summary: "通过伯克希尔历年经营实践，理解企业质量、资本配置、护城河与股东回报。",
            recommendation: "它把抽象的价值投资原则放进长期经营结果里，是观察管理层如何使用资本的好材料。",
            suitableFor: "关注公司基本面、商业模式和管理层资本配置能力的读者。",
            keyIdeas: ["像企业所有者一样思考", "关注长期资本回报", "评估管理层的资本配置"]
        ),
        KnowledgeBook(
            id: "mastering-the-market-cycle",
            title: "周期",
            originalTitle: "Mastering the Market Cycle",
            author: "霍华德·马克斯",
            summary: "认识经济、信贷、情绪与风险偏好如何相互影响，在不确定中判断所处位置。",
            recommendation: "周期无法被精确计时，但理解它能帮助你调整进攻与防守的力度，避免线性外推。",
            suitableFor: "希望把宏观环境、市场情绪与仓位管理联系起来的读者。",
            keyIdeas: ["判断周期所处区间", "观察信贷与风险偏好", "根据环境调整攻守"]
        )
    ]
}

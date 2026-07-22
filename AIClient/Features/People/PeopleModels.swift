import Foundation

struct SpecialPeopleResponse: Decodable {
    let success: Bool
    let users: [SpecialPerson]
}

struct SpecialPerson: Decodable, Identifiable, Hashable {
    let userID: String
    let userName: String?
    let userScreenName: String?
    let userDescription: String?
    let avatarPath: String?
    let todayCount: Int
    let totalCount: Int
    let lastPostTime: String?

    var id: String { userID }
    var isCurated: Bool { userID.hasPrefix("curated:") }
    var isIndustryPerson: Bool { topic == .technology }
    var hasXSource: Bool { Self.aiLeaderXUserIDs.contains(userID) }
    var hasOwnPostSource: Bool { !isCurated || hasXSource }
    var isOrganizationAccount: Bool {
        guard !isIndustryPerson else { return false }
        let identity = (userScreenName ?? name)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let knownOrganizations: Set<String> = [
            "openai", "anthropicai", "googledeepmind", "nvidia",
            "worldcapitalai", "quiverquant", "figurerobot", "deepseekai"
        ]
        if knownOrganizations.contains(identity) { return true }
        let description = (userDescription ?? "").lowercased()
        return description.contains(" is an ai company")
            || description.contains(" is an ai robotics company")
            || description.contains("our mission is")
            || description.contains("we’re hiring")
            || description.contains("we're hiring")
    }
    var name: String { nonempty(userName) ?? nonempty(userScreenName) ?? "未知用户" }
    var handle: String? { nonempty(userScreenName).map { $0.hasPrefix("@") ? $0 : "@\($0)" } }
    var secondaryLabel: String? { isCurated ? nonempty(userScreenName) : handle }
    var organizationName: String? {
        Self.aiLeaderOrganizations[userID] ?? (isCurated ? nonempty(userScreenName) : nil)
    }
    var avatarAssetName: String? {
        switch userID {
        case "curated:xi-jinping": "XiJinpingAvatar"
        case "curated:donald-trump": "DonaldTrumpAvatar"
        case "curated:jack-ma": "JackMaAvatar"
        case "curated:lei-jun": "LeiJunAvatar"
        case "curated:robin-li": "RobinLiAvatar"
        case "curated:dong-mingzhu": "DongMingzhuAvatar"
        case "curated:mao-zedong": "MaoZedongAvatar"
        case "curated:deng-xiaoping": "DengXiaopingAvatar"
        default: nil
        }
    }
    var discussionKeywords: [String] {
        Self.aiLeaderDiscussionKeywords[userID] ?? [name]
    }
    var summary: String {
        if let description = nonempty(userDescription),
           !description.contains("127.0.0.1"), !description.contains("localhost") {
            return description
        }
        return todayCount > 0 ? "今天有 \(todayCount) 条新动态" : "暂无个人简介"
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userName = "user_name"
        case userScreenName = "user_screen_name"
        case userDescription = "user_desc"
        case avatarPath = "avatar_url"
        case todayCount = "today_count"
        case totalCount = "total_count"
        case lastPostTime = "last_post_time"
    }

    init(
        id: String,
        name: String,
        organization: String,
        summary: String,
        avatarURL: String? = nil,
        xUserID: String? = nil,
        xScreenName: String? = nil
    ) {
        userID = xUserID ?? "curated:\(id)"
        userName = name
        userScreenName = xScreenName ?? organization
        userDescription = summary
        avatarPath = avatarURL
        todayCount = 0
        totalCount = 0
        lastPostTime = nil
    }

    func avatarURL(baseURL: URL) -> URL? {
        guard let path = nonempty(avatarPath) else { return nil }
        if let url = URL(string: path), url.scheme != nil {
            let upgraded = path
                .replacingOccurrences(of: "_normal.", with: "_200x200.")
                .replacingOccurrences(of: "_40_normal.", with: "_200x200.")
            return MediaURL.image(upgraded) ?? url
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    var topic: PeopleTopic {
        if Self.politicalFigureIDs.contains(userID) { return .politics }
        if Self.businessFigureIDs.contains(userID) { return .business }
        if Self.historicalFigureIDs.contains(userID) { return .history }
        let identities = [name, userScreenName ?? ""]
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        if identities.contains(where: Self.technologyAccountIdentities.contains) { return .technology }
        if identities.contains(where: Self.investmentAccountIdentities.contains) { return .investment }

        let text = [name, userDescription ?? ""].joined(separator: " ").lowercased()
        if text.contains("总统") || text.contains("政治") || text.contains("government") { return .politics }
        if text.contains("投资") || text.contains("美股") || text.contains("capital") || text.contains("quant") || text.contains("finance") { return .investment }
        if text.contains("历史") || text.contains("history") || text.contains("historian") { return .history }
        if text.contains("科技") || text.contains("ai") || text.contains("openai") || text.contains("人工智能")
            || text.contains("芯片") || text.contains("nvidia") || text.contains("robot") { return .technology }
        return .business
    }

    var relativeTime: String {
        guard let value = nonempty(lastPostTime), let date = Self.dateFormatter.date(from: value) else { return "暂无更新" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86_400 { return "\(seconds / 3_600) 小时前" }
        if seconds < 604_800 { return "\(seconds / 86_400) 天前" }
        return date.formatted(.dateTime.month().day())
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter
    }()
}

extension SpecialPerson {
    fileprivate static let historicalFigureIDs: Set<String> = [
        "curated:mao-zedong", "curated:deng-xiaoping"
    ]
    fileprivate static let businessFigureIDs: Set<String> = [
        "curated:jack-ma", "curated:lei-jun", "curated:robin-li", "curated:dong-mingzhu"
    ]
    fileprivate static let technologyAccountIdentities: Set<String> = [
        "alexandr wang", "alexandr_wang", "jakub pachocki", "merettm",
        "greg brockman", "gdb"
    ]
    fileprivate static let politicalFigureIDs: Set<String> = [
        "curated:xi-jinping",
        "curated:donald-trump"
    ]
    fileprivate static let investmentAccountIdentities: Set<String> = [
        "雪球-但斌",
        "雪球-大道无形我有型",
        "猫笔刀的备忘录",
        "mooomoocat"
    ]
    fileprivate static let aiLeaderXUserIDs: Set<String> = [
        "1605", "874126509245476864", "1482581556", "44196397",
        "20571756", "14130366", "20749410"
    ]
    fileprivate static let aiLeaderOrganizations: [String: String] = [
        "1605": "OpenAI 联合创始人兼 CEO",
        "874126509245476864": "Anthropic 联合创始人兼 CEO",
        "1482581556": "Google DeepMind 联合创始人兼 CEO",
        "44196397": "xAI 创始人",
        "20571756": "Microsoft 董事长兼 CEO",
        "14130366": "Google 与 Alphabet CEO",
        "20749410": "Meta 创始人兼 CEO"
    ]
    fileprivate static let aiLeaderDiscussionKeywords: [String: [String]] = [
        "curated:jack-ma": ["马云", "Jack Ma", "阿里巴巴"],
        "curated:lei-jun": ["雷军", "小米"],
        "curated:robin-li": ["李彦宏", "Robin Li", "百度"],
        "curated:dong-mingzhu": ["董明珠", "格力"],
        "curated:mao-zedong": ["毛泽东", "Mao Zedong"],
        "curated:deng-xiaoping": ["邓小平", "Deng Xiaoping", "改革开放"],
        "curated:xi-jinping": ["习近平", "Xi Jinping"],
        "curated:donald-trump": ["特朗普", "Donald Trump", "Trump"],
        "1605": ["奥特曼", "Sam Altman"],
        "874126509245476864": ["阿莫迪", "Dario Amodei"],
        "1482581556": ["哈萨比斯", "Demis Hassabis"],
        "44196397": ["马斯克", "Elon Musk"],
        "20571756": ["纳德拉", "Satya Nadella"],
        "14130366": ["皮查伊", "Sundar Pichai"],
        "20749410": ["扎克伯格", "马克·扎克伯格", "Mark Zuckerberg"]
    ]

    static let artificialIntelligenceLeaders: [SpecialPerson] = [
        .init(id: "sam-altman", name: "Sam Altman", organization: "OpenAI", summary: "OpenAI 联合创始人兼 CEO，推动生成式人工智能产品与前沿模型发展。", avatarURL: "https://pbs.twimg.com/profile_images/2046764873200394240/r7BxVezs_normal.jpg", xUserID: "1605", xScreenName: "sama"),
        .init(id: "dario-amodei", name: "Dario Amodei", organization: "Anthropic", summary: "Anthropic 联合创始人兼 CEO，长期关注大模型能力与人工智能安全。", avatarURL: "https://pbs.twimg.com/profile_images/2015835742577012736/uOwdzrEz_normal.jpg", xUserID: "874126509245476864", xScreenName: "DarioAmodei"),
        .init(id: "demis-hassabis", name: "Demis Hassabis", organization: "Google DeepMind", summary: "Google DeepMind 联合创始人兼 CEO，领导 Gemini、AlphaFold 等研究。", avatarURL: "https://pbs.twimg.com/profile_images/1990472620614053888/xrAu0wQL_normal.jpg", xUserID: "1482581556", xScreenName: "demishassabis"),
        .init(id: "jensen-huang", name: "黄仁勋", organization: "NVIDIA", summary: "NVIDIA 创始人兼 CEO，推动 GPU 计算平台成为人工智能基础设施核心。", avatarURL: "https://iprsoftwaremedia.com/219/files/202604/f0e9efa72f909f3f08cdd0a48ff92880/69e6b9293d633260eec67804_jensen-1920x1920/jensen-1920x1920_6a7e6ad5-c215-4503-b70d-fe6e5e9de205-prv.jpg"),
        .init(id: "elon-musk", name: "Elon Musk", organization: "xAI", summary: "xAI 创始人，推动 Grok 系列模型及大规模人工智能算力建设。", avatarURL: "https://pbs.twimg.com/profile_images/2053244804520427520/m8mdWZCG_normal.jpg", xUserID: "44196397", xScreenName: "elonmusk"),
        .init(id: "liang-wenfeng", name: "梁文锋", organization: "DeepSeek", summary: "DeepSeek 创始人兼 CEO，专注高效训练、推理与开源大模型。", avatarURL: "https://x0.ifengimg.com/ucms/2025_07/6B3B6F2370B03F5951EE64319BC45032A833995D_size486_w975_h549.png"),
        .init(id: "satya-nadella", name: "Satya Nadella", organization: "Microsoft", summary: "Microsoft 董事长兼 CEO，推动云计算与人工智能成为公司的核心战略。", avatarURL: "https://pbs.twimg.com/profile_images/1221837516816306177/_Ld4un5A_normal.jpg", xUserID: "20571756", xScreenName: "satyanadella"),
        .init(id: "sundar-pichai", name: "Sundar Pichai", organization: "Google", summary: "Google 与 Alphabet CEO，领导 Gemini 等人工智能产品和基础设施发展。", avatarURL: "https://pbs.twimg.com/profile_images/2051799620062429184/AL8CoAUG_normal.jpg", xUserID: "14130366", xScreenName: "sundarpichai"),
        .init(id: "mark-zuckerberg", name: "Mark Zuckerberg", organization: "Meta", summary: "Meta 创始人兼 CEO，推动开源大模型 Llama、智能眼镜与下一代计算平台。", avatarURL: "https://pbs.twimg.com/profile_images/77846223/profile_normal.jpg", xUserID: "20749410", xScreenName: "finkd")
    ]

    static let politicalFigures: [SpecialPerson] = [
        .init(id: "xi-jinping", name: "习近平", organization: "中国政治人物", summary: "关注中国政治、外交与公共政策相关动态。"),
        .init(id: "donald-trump", name: "Donald Trump", organization: "美国政治人物", summary: "关注美国政治、外交与公共政策相关动态。")
    ]

    static let chineseEntrepreneurs: [SpecialPerson] = [
        .init(id: "jack-ma", name: "马云", organization: "阿里巴巴创始人", summary: "关注商业创新、创业与数字经济相关动态。"),
        .init(id: "lei-jun", name: "雷军", organization: "小米集团创始人", summary: "关注企业经营、消费品牌与智能制造相关动态。"),
        .init(id: "robin-li", name: "李彦宏", organization: "百度创始人", summary: "关注企业战略、互联网与产业发展相关动态。"),
        .init(id: "dong-mingzhu", name: "董明珠", organization: "格力电器董事长", summary: "关注企业管理、制造业与消费市场相关动态。")
    ]

    static let historicalFigures: [SpecialPerson] = [
        .init(id: "mao-zedong", name: "毛泽东", organization: "中国近现代历史人物", summary: "关注中国近现代史及相关历史讨论。"),
        .init(id: "deng-xiaoping", name: "邓小平", organization: "中国近现代历史人物", summary: "关注改革开放及中国近现代史相关讨论。")
    ]
}

private func nonempty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}

enum PeopleTopic: String, CaseIterable, Identifiable {
    case technology = "科技"
    case business = "商业"
    case politics = "政治"
    case investment = "投资"
    case history = "历史"

    var id: Self { self }
}

import Foundation

struct LearningCatalog: Equatable {
    let sections: [LearningSection]

    var topicCount: Int {
        sections.reduce(0) { $0 + $1.topics.count }
    }
}
struct LearningSection: Identifiable, Equatable {
    let name: String
    let topics: [LearningTopic]

    var id: String { name }
}

struct LearningTopic: Identifiable, Hashable {
    let title: String
    let summary: String
    let url: URL
    let category: String

    var id: String { url.absoluteString }
}

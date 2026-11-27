import SwiftUI

private struct AgendaEvent: Decodable, Identifiable {
    let id, date, title, kind, region, status, detail, source: String
    let time, publishedAt: String?
    let sourceURL: URL
    var statusLabel: String {
        switch status {
        case "announced": "官方日程"
        case "published": "已发通稿"
        case "estimated": "观察窗口"
        default: "待确认"
        }
    }
    var tint: Color { status == "estimated" ? .orange : ResearchDesign.accent }
}

private struct AgendaSnapshot: Decodable {
    let reviewedOn: String
    let reportsUnavailable: Bool?
    let events: [AgendaEvent]
}

private struct AgendaResponse: Decodable { let data: AgendaSnapshot }

struct MarketAgendaView: View {
    @State private var month = Self.startOfMonth(Date())
    @State private var selected: Date? = nil
    @State private var range: RangeChoice = .week
    @State private var filter = "全部市场"
    @State private var category = "全部类别"
    @State private var loadedQuery = ""
    @State private var snapshot: AgendaSnapshot?
    @State private var failed = false
    @State private var requestID = UUID()
    @State private var expanded: Set<String> = []

    private enum RangeChoice: String, CaseIterable {
        case day = "当天", week = "未来 7 天", upcoming = "未来 30 天"
    }
    private static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        value.firstWeekday = 2
        return value
    }()
    private static func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }
    private func key(_ date: Date) -> String {
        let c = Self.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    private var today: Date { Self.calendar.startOfDay(for: Date()) }
    private var query: (from: Date, to: Date) {
        let c = Self.calendar
        if range == .day {
            let end = c.date(byAdding: .day, value: -1, to: c.date(byAdding: .month, value: 1, to: month) ?? month) ?? month
            return (month, end)
        }
        let days = range == .week ? 6 : 29
        let end = c.date(byAdding: .day, value: days, to: today) ?? today
        let next = c.date(byAdding: .month, value: 1, to: Self.startOfMonth(today)) ?? today
        let monthEnd = c.date(byAdding: .day, value: -1, to: next) ?? end
        return (Self.startOfMonth(today), max(end, monthEnd))
    }
    private var queryKey: String { "\(key(query.from))/\(key(query.to))/\(requestID)" }
    private var visible: [AgendaEvent] {
        let all = loadedQuery == queryKey ? snapshot?.events ?? [] : []
        let markets = ["中国": "CN", "美国": "US", "香港": "HK"]
        let kinds = ["政策": "policy", "数据": "data", "会议": "meeting", "财报": "earnings"]
        let end = Self.calendar.date(byAdding: .day, value: range == .week ? 6 : 29, to: today) ?? today
        return all.filter { e in
            guard markets[filter].map({ $0 == e.region }) ?? true, kinds[category].map({ $0 == e.kind }) ?? true else { return false }
            if range == .day { return selected.map { key($0) == e.date } ?? false }
            return e.date >= key(today) && e.date <= key(end)
        }.sorted { ($0.date, $0.time ?? "99:99", $0.title) < ($1.date, $1.time ?? "99:99", $1.title) }
    }
    private var daysWithEvents: Set<String> { Set((loadedQuery == queryKey ? snapshot?.events ?? [] : []).map(\.date)) }
    private var grouped: [(date: String, events: [AgendaEvent])] {
        let groups = Dictionary(grouping: visible, by: \.date)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("大事日历").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("政策会议 · 宏观数据 · 公司财报").font(.subheadline).foregroundStyle(.secondary)
                }
                monthGrid
                Picker("时间范围", selection: $range) {
                    ForEach(RangeChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                    .onChange(of: range) { _, next in
                        if next == .day { selected = selected ?? min(max(today, month), monthEnd) }
                        else { month = Self.startOfMonth(today); selected = nil }
                    }
                HStack {
                    Picker("市场", selection: $filter) {
                        ForEach(["全部市场", "中国", "美国", "香港"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("类别", selection: $category) {
                        ForEach(["全部类别", "政策", "数据", "会议", "财报"], id: \.self) { Text($0).tag($0) }
                    }
                    Spacer()
                    if let snapshot {
                        Text("核对于 \(snapshot.reviewedOn)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if failed {
                    Text("日历暂时无法更新").font(.footnote).foregroundStyle(.secondary)
                    Button("重试") { requestID = UUID() }
                } else if loadedQuery != queryKey {
                    ProgressView("载入日历中…")
                } else if visible.isEmpty {
                    ContentUnavailableView("没有收录的日程", systemImage: "calendar", description: Text("可切换日期或市场；未收录不代表没有事件。"))
                }
                ForEach(grouped, id: \.date) { group in
                    Text(group.date).font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(group.events) { event in eventRow(event) }
                }
                if snapshot?.reportsUnavailable == true, loadedQuery == queryKey {
                    Label("财报来源暂不可用", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                Text("时间以北京时间显示；没有公开时刻的事项不补时间。观察窗口不是官方预告。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(InvestmentDesign.surface)
        .accessibilityIdentifier("market-agenda")
        .task(id: queryKey) { await load() }
        .refreshable { await load() }
    }

    private var monthEnd: Date {
        let c = Self.calendar
        return c.date(byAdding: .day, value: -1, to: c.date(byAdding: .month, value: 1, to: month) ?? month) ?? month
    }
    private func moveMonth(_ offset: Int) {
        guard let next = Self.calendar.date(byAdding: .month, value: offset, to: month) else { return }
        month = next
        selected = next
        range = .day
    }
    private var monthGrid: some View {
        let c = Self.calendar
        let blanks = (c.component(.weekday, from: month) + 5) % 7
        let days = c.range(of: .day, in: .month, for: month)?.count ?? 0
        return VStack(spacing: 8) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("上个月")
                Spacer()
                Text("\(c.component(.year, from: month)) 年 \(c.component(.month, from: month)) 月")
                    .font(.headline)
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("下个月")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(["一","二","三","四","五","六","日"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 1).accessibilityHidden(true) }
                ForEach(0..<days, id: \.self) { index in
                    if let date = c.date(byAdding: .day, value: index, to: month) {
                        let active = selected == date || (range != .day && date == today)
                        let dot = daysWithEvents.contains(key(date))
                        Button {
                            selected = date
                            range = .day
                        } label: {
                            VStack(spacing: 3) {
                                Text((index + 1).formatted()).font(.subheadline.weight(active ? .bold : .regular))
                                Circle().fill(dot ? ResearchDesign.accent : .clear).frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(active ? ResearchDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key(date) + (dot ? "，有日程" : ""))
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func eventRow(_ event: AgendaEvent) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(event.id) },
            set: { if $0 { expanded.insert(event.id) } else { expanded.remove(event.id) } }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.detail).font(.subheadline)
                if let at = event.publishedAt {
                    Text("通稿发布：\(at)").font(.caption).foregroundStyle(.secondary)
                }
                Link(event.source, destination: event.sourceURL).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(event.time ?? "时刻未列").foregroundStyle(.secondary).monospacedDigit()
                    Text(event.statusLabel).foregroundStyle(event.tint)
                }.font(.caption)
            }
        }
        .padding(12)
        .background(ResearchDesign.selection.opacity(0.48), in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor private func load() async {
        let target = query
        let loadID = queryKey
        let url = ServerConfiguration.currentURL.appending(path: "api/ios/v1/market/agenda")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "from", value: key(target.from)), URLQueryItem(name: "to", value: key(target.to))]
        guard let endpoint = components.url else { return }
        failed = false
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: endpoint, timeoutInterval: 10))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let value = try JSONDecoder().decode(AgendaResponse.self, from: data).data
            guard !Task.isCancelled, loadID == queryKey else { return }
            snapshot = value
            loadedQuery = loadID
        } catch {
            if !Task.isCancelled, loadID == queryKey { failed = true }
        }
    }
}

import SwiftUI

private struct AgendaEvent: Decodable, Identifiable {
    let id, date, title, kind, region, status, detail, source: String
    let time, publishedAt, endDate: String?
    let sourceURL: URL
    func overlaps(_ start: String, _ end: String) -> Bool {
        date <= end && (endDate ?? date) >= start
    }

    var statusLabel: String {
        switch status {
        case "announced": "官方日程"
        case "published": "已发通稿"
        case "estimated": "观察窗口"
        default: "待确认"
        }
    }
    var marketLabel: String {
        switch region {
        case "CN": "中国"
        case "US": "美国"
        case "HK": "香港"
        default: region
        }
    }

    var kindLabel: String {
        switch kind {
        case "policy": "政策"
        case "data": "宏观数据"
        case "meeting": "会议"
        case "earnings": "公司财报"
        default: "日程"
        }
    }
}

private struct AgendaSnapshot: Decodable {
    let reviewedOn: String
    let reportsUnavailable: Bool?
    let events: [AgendaEvent]
}

private struct AgendaResponse: Decodable { let data: AgendaSnapshot }

private enum AgendaPalette {
    static let ink = Color(red: 0.09, green: 0.17, blue: 0.14)
    static let muted = Color(red: 0.30, green: 0.38, blue: 0.34)
    static let green = Color(red: 0.09, green: 0.39, blue: 0.32)
    static let mint = Color(red: 0.88, green: 0.94, blue: 0.91)
    static let subtle = Color(red: 0.94, green: 0.96, blue: 0.95)
    static let line = Color(red: 0.87, green: 0.91, blue: 0.89)
    static let rail = Color(red: 0.77, green: 0.85, blue: 0.81)
    static let amber = Color(red: 0.44, green: 0.28, blue: 0.11)
    static let amberBackground = Color(red: 0.99, green: 0.96, blue: 0.90)
    static let amberLine = Color(red: 0.92, green: 0.86, blue: 0.73)
}

struct MarketAgendaView: View {
    let onClose: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth = 56
    @State private var showsMonth = false
    @State private var month = Self.startOfMonth(Date())
    @State private var selected: Date? = nil
    @State private var range: RangeChoice = .week
    @State private var filter = "全部"
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
    private var displayedStart: Date { range == .day ? selected ?? today : today }
    private var displayedEnd: Date {
        let days = range == .day ? 0 : range == .week ? 6 : 29
        return Self.calendar.date(byAdding: .day, value: days, to: displayedStart) ?? displayedStart
    }
    private var query: (from: Date, to: Date) {
        if range == .day { return (month, monthEnd) }
        let thisMonth = Self.startOfMonth(today)
        return (thisMonth, max(displayedEnd, Self.calendarEnd(of: thisMonth)))
    }
    private var queryKey: String { "\(key(query.from))/\(key(query.to))/\(requestID)" }
    private static let markets = ["全部", "中国", "美国", "香港"]
    private static let categories = ["全部类别", "政策", "数据", "会议", "财报"]
    private var visible: [AgendaEvent] {
        let all = loadedQuery == queryKey ? snapshot?.events ?? [] : []
        let markets = ["中国": "CN", "美国": "US", "香港": "HK"]
        let kinds = ["政策": "policy", "数据": "data", "会议": "meeting", "财报": "earnings"]
        let first = key(displayedStart), last = key(displayedEnd)
        return all.filter { event in
            (markets[filter].map { $0 == event.region } ?? true)
                && (kinds[category].map { $0 == event.kind } ?? true)
                && event.overlaps(first, last)
        }.sorted { ($0.date, $0.time ?? "99:99", $0.title) < ($1.date, $1.time ?? "99:99", $1.title) }
    }
    private var monthEvents: [AgendaEvent] { loadedQuery == queryKey ? snapshot?.events ?? [] : [] }
    private func grouped(_ events: [AgendaEvent]) -> [(date: String, events: [AgendaEvent])] {
        let start = key(displayedStart)
        let groups = Dictionary(grouping: events) { max(start, $0.date) }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }
    private func dateLabel(_ date: Date) -> String {
        let c = Self.calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }
    private func dayHeading(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return iso }
        let week = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return String(format: "%02d/%02d", parts[1], parts[2]) + "　" + week[Self.calendar.component(.weekday, from: date) - 1]
    }
    private var rangeDescription: String {
        let first = dateLabel(displayedStart)
        if range == .day { return first + " · 北京时间" }
        let sameMonth = Self.calendar.isDate(displayedStart, equalTo: displayedEnd, toGranularity: .month)
        return (sameMonth
            ? "\(Self.calendar.component(.month, from: displayedStart)) 月 \(Self.calendar.component(.day, from: displayedStart))–\(Self.calendar.component(.day, from: displayedEnd)) 日"
            : first + "至" + dateLabel(displayedEnd)) + " · 北京时间"
    }

    var body: some View {
        ScrollView {
            let events = visible
            let windows = events.filter { $0.status == "estimated" }
            let days = grouped(events.filter { $0.status != "estimated" })

            LazyVStack(alignment: .leading, spacing: 13) {
                header
                rangePicker
                filters

                if failed {
                    Text("日历暂时无法更新").font(.footnote).foregroundStyle(AgendaPalette.muted)
                    Button("重试") { requestID = UUID() }
                } else if loadedQuery != queryKey {
                    ProgressView("载入日历中…")
                } else if events.isEmpty {
                    ContentUnavailableView("没有收录的日程", systemImage: "calendar", description: Text("可切换日期或市场；未收录不代表没有事件。"))
                }

                ForEach(windows) { windowCard($0) }
                if !days.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(days, id: \.date) { day in
                            timelineDay(day.date, events: day.events)
                        }
                    }
                    .background(alignment: .leading) {
                        Rectangle().fill(AgendaPalette.rail).frame(width: 1).padding(.leading, 6)
                    }
                }

                if snapshot?.reportsUnavailable == true, loadedQuery == queryKey {
                    Label("财报来源暂不可用", systemImage: "info.circle").font(.caption).foregroundStyle(AgendaPalette.muted)
                }
                if let snapshot, loadedQuery == queryKey {
                    Text("核对日期：\(snapshot.reviewedOn) · 观察窗口不是官方预告")
                        .font(.caption).foregroundStyle(AgendaPalette.muted)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.white)
        .foregroundStyle(AgendaPalette.ink)
        .tint(AgendaPalette.green)
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("market-agenda")
        .appSheet(isPresented: $showsMonth) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("选择日期").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("完成") { showsMonth = false }.frame(minHeight: 44)
                }
                monthGrid
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
            .foregroundStyle(AgendaPalette.ink)
            .tint(AgendaPalette.green)
            .environment(\.colorScheme, .light)
        }
        .task(id: queryKey) { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button(action: onClose) {
                    Label("研究", systemImage: "chevron.left")
                        .font(.subheadline)
                        .foregroundStyle(AgendaPalette.muted)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回研究")
                Spacer()
                Button { showsMonth = true } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(AgendaPalette.ink)
                        .frame(width: 44, height: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AgendaPalette.line) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开月历")
            }
            Text("大事日历").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(rangeDescription).font(.footnote).foregroundStyle(AgendaPalette.muted)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(RangeChoice.allCases, id: \.self) { option in
                Button {
                    month = Self.startOfMonth(today)
                    selected = option == .day ? today : nil
                    range = option
                } label: {
                    Text(option.rawValue)
                        .font(.footnote.weight(range == option ? .semibold : .medium))
                        .minimumScaleFactor(0.84)
                        .foregroundStyle(range == option ? AgendaPalette.green : AgendaPalette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.vertical, 1)
                        .background(range == option ? AgendaPalette.mint : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(range == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AgendaPalette.subtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Self.markets, id: \.self) { market in
                    Button { filter = market } label: { chip(market, active: filter == market) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == market ? .isSelected : [])
                }
                Menu {
                    Picker("类别", selection: $category) {
                        ForEach(Self.categories, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    chip(category == "全部类别" ? "类别" : category, active: category != "全部类别", menu: true)
                }
                .accessibilityLabel("类别：\(category)")
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ text: String, active: Bool, menu: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(text)
            if menu { Image(systemName: "chevron.down").font(.caption2) }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(active ? AgendaPalette.green : AgendaPalette.muted)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(active ? AgendaPalette.mint : .white, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(active ? .clear : AgendaPalette.line) }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func timelineDay(_ date: String, events: [AgendaEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayHeading(date))
                    .font(.subheadline.bold()).monospacedDigit()
                    .foregroundStyle(AgendaPalette.green)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Text("\(events.count) 项日程").font(.caption).foregroundStyle(AgendaPalette.muted)
            }
            .padding(.vertical, 3)
            .overlay(alignment: .leading) {
                Circle().fill(AgendaPalette.green)
                    .frame(width: 7, height: 7)
                    .padding(3)
                    .background(AgendaPalette.mint, in: Circle())
                    .offset(x: -21)
                    .accessibilityHidden(true)
            }
            ForEach(events) { event in
                eventRow(event)
                if event.id != events.last?.id { Rectangle().fill(AgendaPalette.line).frame(height: 1) }
            }
        }
        .padding(.leading, 21)
    }

    private func windowCard(_ event: AgendaEvent) -> some View {
        let isOpen = expanded.contains(event.id)
        let title = event.title.components(separatedBy: "：").first ?? event.title
        let interval = event.endDate.map { String(event.date.suffix(5)).replacingOccurrences(of: "-", with: "/")
            + "–" + String($0.suffix(5)).replacingOccurrences(of: "-", with: "/") }
        return VStack(alignment: .leading, spacing: 6) {
            Button { toggle(event.id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "flag").accessibilityHidden(true)
                    Text(title).fontWeight(.semibold)
                    Spacer(minLength: 4)
                    Text(interval.map { $0 + " · 估计" } ?? "估计")
                        .font(.caption).monospacedDigit().multilineTextAlignment(.trailing)
                }
                .font(.footnote)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "收起详情" : "展开详情")
            if isOpen { eventDetail(event) }
        }
        .foregroundStyle(AgendaPalette.amber)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AgendaPalette.amberBackground, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(AgendaPalette.amberLine) }
    }

    private var monthEnd: Date { Self.calendarEnd(of: month) }

    private static func calendarEnd(of month: Date) -> Date {
        let next = calendar.date(byAdding: .month, value: 1, to: month) ?? month
        return calendar.date(byAdding: .day, value: -1, to: next) ?? month
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
                        let day = key(date)
                        let dot = monthEvents.contains { $0.overlaps(day, day) }
                        Button {
                            selected = date
                            range = .day
                            showsMonth = false
                        } label: {
                            VStack(spacing: 3) {
                                Text((index + 1).formatted()).font(.subheadline.weight(active ? .bold : .regular))
                                Circle().fill(dot ? AgendaPalette.green : .clear).frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(active ? AgendaPalette.mint : .clear, in: RoundedRectangle(cornerRadius: 8))
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

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func eventRow(_ event: AgendaEvent) -> some View {
        let isOpen = expanded.contains(event.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button { toggle(event.id) } label: {
                HStack(alignment: .center, spacing: 10) {
                    Text(event.time ?? "时间未定")
                        .font(event.time == nil ? .caption : .subheadline.weight(.semibold))
                        .monospacedDigit().foregroundStyle(AgendaPalette.muted)
                        .frame(width: timeWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(AgendaPalette.ink)
                        Text(event.marketLabel + " · " + event.kindLabel + (event.status == "announced" ? "" : " · " + event.statusLabel))
                            .font(.caption).foregroundStyle(AgendaPalette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(AgendaPalette.green)
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "收起详情" : "展开详情")
            if isOpen {
                eventDetail(event)
                    .padding(.leading, timeWidth + 10)
                    .padding(.bottom, 11)
            }
        }
    }

    private func eventDetail(_ event: AgendaEvent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(event.detail).font(.subheadline).foregroundStyle(AgendaPalette.ink)
            if let end = event.endDate {
                Text("\(event.date) 至 \(end)").font(.caption).foregroundStyle(AgendaPalette.muted)
            }
            if let at = event.publishedAt {
                Text("通稿发布：\(at)").font(.caption).foregroundStyle(AgendaPalette.muted)
            }
            Link(event.source, destination: event.sourceURL)
                .font(.caption)
                .foregroundStyle(AgendaPalette.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
